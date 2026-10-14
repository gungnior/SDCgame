#Requires -Version 5.1
<#
.SYNOPSIS
  push 前检查清单 —— 两人协作的入库门禁（pre_push_check）。

.DESCRIPTION
  在推 remote 之前逐项检查，任何一项 FAIL 就不该 push：
    1. 工作树干净            —— 脏树推上去 = 把半成品送给队友
    2. 无超大文件入库        —— >5MB 警告、>20MB 失败（防 APK/二进制误入）
    3. 工具链/产物未入库     —— _install/ build/ .godot/ .workbuddy/ 被跟踪就挂
    4. 无密钥凭据文件        —— *.keystore/*.jks/*.p12/*.pem/.env
    5. 含非 ASCII 的 *.ps1 均带 UTF-8 BOM —— Win PowerShell 5.1 不带 BOM 按 ANSI 读，中文注释直接崩解析器（纯 ASCII 的豁免，不误报）
    6. 验收退出码 0          —— verify_all.ps1 -Fast（只改文档可用 -SkipVerify 跳过）
    7. remote 已配置         —— 没配 origin 就打印配置命令，不猜
    8. 探针脚本能跑          —— test/*probe*.gd 逐个 headless 跑（20s 超时）；需真人交互的登记豁免

.PARAMETER SkipVerify
  跳过第 6 项验收（只动了 specs/*.md 之类的文档时用，省 20 秒）。

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File tools\pre_push_check.ps1

.NOTES
  退出码 0 = 全过可以 push；1 = 有 FAIL，修完再来。
  本脚本自身遵守项目约定：相对项目根定位（Split-Path $PSScriptRoot），不写死盘符。
#>
param([switch]$SkipVerify)

$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$script:Failed = 0

function Step([string]$Name, [bool]$Ok, [string]$Detail) {
    $mark = "PASS"
    if (-not $Ok) { $mark = "FAIL"; $script:Failed++ }
    Write-Output ("  [{0}] {1} -- {2}" -f $mark, $Name, $Detail)
}

Write-Output "=== pre-push 检查（根：$Root） ==="

# ---- 1. 工作树干净 ----
$dirty = @(& git status --porcelain)
Step "1. 工作树干净" ($dirty.Count -eq 0) ("未提交条目 {0} 个" -f $dirty.Count)
if ($dirty.Count -gt 0) {
    $dirty | Select-Object -First 10 | ForEach-Object { Write-Output "        $_" }
    if ($dirty.Count -gt 10) { Write-Output "        ...（其余略）" }
}

# ---- 2. 超大文件 ----
$tracked = @(& git ls-files)
$big = @($tracked | ForEach-Object {
    $p = Join-Path $Root ($_ -replace '/', '\')
    if (Test-Path -LiteralPath $p) {
        $len = (Get-Item -LiteralPath $p).Length
        if ($len -gt 5MB) {
            [pscustomobject]@{ Path = $_; MB = [math]::Round($len / 1MB, 2) }
        }
    }
})
$over20 = @($big | Where-Object { $_.MB -gt 20 })
Step "2. 无超大文件入库" ($over20.Count -eq 0) (">5MB {0} 个 / >20MB {1} 个" -f $big.Count, $over20.Count)
foreach ($b in $big) { Write-Output ("        {0}  {1} MB" -f $b.Path, $b.MB) }

# ---- 3. 不该入库的目录 ----
$badDirs = @($tracked | Where-Object {
    $_ -match '^(_install/|build/|\.godot/|\.workbuddy/|godot/\.godot/|_nightrun/|\.dsh/|\.dsh-home/)'
})
Step "3. 工具链/产物未入库" ($badDirs.Count -eq 0) ("命中 {0} 个：{1}" -f $badDirs.Count, ($badDirs -join ', '))

# ---- 4. 密钥凭据 ----
$secrets = @($tracked | Where-Object {
    $_ -match '\.(keystore|jks|p12|pem|key)$' -or $_ -match '(^|/)\.env' -or $_ -match 'credentials'
})
Step "4. 无密钥凭据文件" ($secrets.Count -eq 0) ("命中 {0} 个：{1}" -f $secrets.Count, ($secrets -join ', '))

# ---- 5. .ps1 BOM ----
# 内容感知判定：含非 ASCII 且缺 BOM 才会被 PS 5.1 按 ANSI 读崩 -> FAIL；
# 纯 ASCII 的 .ps1 没 BOM 也能正常跑 -> 放行但注明（不误报）。
$ps1s = @($tracked | Where-Object { $_ -match '\.ps1$' })
$noBom = @()
$asciiOnly = @()
foreach ($f in $ps1s) {
    $p = Join-Path $Root ($f -replace '/', '\')
    if (Test-Path -LiteralPath $p) {
        $b = [System.IO.File]::ReadAllBytes($p)
        $hasBom = ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)
        if (-not $hasBom) {
            $text = [System.Text.Encoding]::UTF8.GetString($b)
            if ($text -match '[^\x00-\x7F]') { $noBom += $f } else { $asciiOnly += $f }
        }
    }
}
$d5 = ("检查 {0} 个；含非 ASCII 且缺 BOM：{1}" -f $ps1s.Count, ($noBom -join ', '))
if ($asciiOnly.Count -gt 0) {
    $d5 += ("；纯 ASCII 免 BOM {0} 个（{1}）" -f $asciiOnly.Count, ($asciiOnly -join ', '))
}
Step "5. *.ps1 含中文时均带 UTF-8 BOM" ($noBom.Count -eq 0) $d5

# ---- 6. 验收 ----
if ($SkipVerify) {
    Step "6. 验收（-SkipVerify 跳过）" $true "仅限纯文档改动时用"
} else {
    Write-Output "  ... 跑 verify_all.ps1 -Fast（约 20 秒，期间别动鼠标）..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root "tools\verify_all.ps1") -Fast
    $code = $LASTEXITCODE
    Step "6. verify_all.ps1 -Fast 退出码 0" ($code -eq 0) ("exit={0}" -f $code)
}

# ---- 7. remote ----
$null = & git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $(& git remote get-url origin 2>$null)) {
    $url = & git remote get-url origin
    Step "7. remote 已配置" $true $url
} else {
    Step "7. remote 已配置" $false "未配置 origin —— 先建库再 add（命令见下）"
    Write-Output ""
    Write-Output "    git remote add origin <你的仓库地址>"
    Write-Output "    git push -u origin master"
}


# ---- 8. 探针脚本能跑（2026-10-13 新增）----
# 为什么：test/*probe*.gd 是"一次性诊断工具"，此前**没有任何地方保证它们还能跑** ——
#   而"写了却没人执行"正是本项目被咬过的形态（见 run_tests.gd 的注册守卫）。
# 做法：逐个 headless 跑（20 秒超时），退出码非 0 或超时即 FAIL。
#   需要**真人交互**的那几个登记在 $probeSkip 里并写明理由 —— 不静默跳过，
#   "必须能跑，或登记一个理由"。（豁免清单是 2026-10-13 逐个实测出来的，不是猜的。）
$probeSkip = @(
    "test/hideout_probe.gd",   # 需要真人点选藏身处界面，headless 下等不到输入 -> 必然超时
    "test/menu_probe.gd",      # 同上（主菜单要点）
    "test/merchant_probe.gd",  # 同上（商人面板要点）
    "test/result_probe.gd"     # 同上（结算界面要点）
)
$probes = @($tracked | Where-Object { $_ -match '^test/.*probe.*\.gd$' })
$godotExe = Join-Path $Root "_install\godot\Godot_v4.7.2-stable_win64_console.exe"
if ($probes.Count -eq 0) {
    Step "8. 探针脚本能跑" $true "tracked 里没有 test/*probe*.gd"
} elseif (-not (Test-Path -LiteralPath $godotExe)) {
    Step "8. 探针脚本能跑" $false ("找不到 Godot：{0}（{1} 个探针未验证）" -f $godotExe, $probes.Count)
} else {
    $probeFail = @()
    $probeRan = 0
    $probeOut = Join-Path $env:TEMP "probe_smoke_out.txt"
    foreach ($f in $probes) {
        if ($probeSkip -contains $f) { continue }
        $scene = ($f -replace '\.gd$', '.tscn')
        if (Test-Path -LiteralPath (Join-Path $Root ($scene -replace '/', '\'))) {
            $a2 = @('--headless', '--path', '.', ('res://' + $scene))
        } else {
            $a2 = @('--headless', '--path', '.', '--script', ('res://' + $f))
        }
        $proc = Start-Process -FilePath $godotExe -ArgumentList $a2 -PassThru -NoNewWindow -RedirectStandardOutput $probeOut -RedirectStandardError ($probeOut + ".err")
        $probeRan++
        if (-not $proc.WaitForExit(20000)) {
            $proc.Kill()
            $probeFail += ($f + "(超时20s)")
        } else {
            # ⚠️ 用了 -RedirectStandardOutput 时，必须再等一次**无参** WaitForExit，
            #    否则异步输出流尚未收尾，$proc.ExitCode 会是 $null —— 而 `$null -ne 0` 为真，
            #    会把"跑得好好的探针"**全部误判成失败**（2026-10-13 实测踩到，正是本项自己抓出来的）。
            $proc.WaitForExit()
            $ec = $proc.ExitCode
            if ($null -eq $ec) { $probeFail += ($f + "(退出码读不到)") }
            elseif ($ec -ne 0) { $probeFail += ($f + "(exit=$ec)") }
        }
    }
    Remove-Item $probeOut, ($probeOut + ".err") -ErrorAction SilentlyContinue
    $d8 = ("{0} 个探针：跑 {1} / 豁免 {2} / 失败 {3}" -f $probes.Count, $probeRan, $probeSkip.Count, $probeFail.Count)
    if ($probeFail.Count -gt 0) { $d8 += (" -> " + ($probeFail -join ', ')) }
    Step "8. 探针脚本能跑" ($probeFail.Count -eq 0) $d8
    if ($probeSkip.Count -gt 0) { Write-Output ("        豁免（需真人交互）：" + ($probeSkip -join ', ')) }
}
# ---- 汇总 ----
Write-Output ""
if ($script:Failed -eq 0) {
    Write-Output "=== 全部通过 —— 可以 push ==="
    exit 0
} else {
    Write-Output ("=== {0} 项未过 —— 修完再 push ===" -f $script:Failed)
    exit 1
}

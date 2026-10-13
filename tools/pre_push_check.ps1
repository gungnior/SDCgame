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
    5. *.ps1 均带 UTF-8 BOM  —— Win PowerShell 5.1 不带 BOM 按 ANSI 读，中文注释直接崩解析器
    6. 验收退出码 0          —— verify_all.ps1 -Fast（只改文档可用 -SkipVerify 跳过）
    7. remote 已配置         —— 没配 origin 就打印配置命令，不猜

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
$ps1s = @($tracked | Where-Object { $_ -match '\.ps1$' })
$noBom = @()
foreach ($f in $ps1s) {
    $p = Join-Path $Root ($f -replace '/', '\')
    if (Test-Path -LiteralPath $p) {
        $b = [System.IO.File]::ReadAllBytes($p)
        if (-not ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF)) {
            $noBom += $f
        }
    }
}
Step "5. *.ps1 均带 UTF-8 BOM" ($noBom.Count -eq 0) ("检查 {0} 个，缺 BOM：{1}" -f $ps1s.Count, ($noBom -join ', '))

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

# ---- 汇总 ----
Write-Output ""
if ($script:Failed -eq 0) {
    Write-Output "=== 全部通过 —— 可以 push ==="
    exit 0
} else {
    Write-Output ("=== {0} 项未过 —— 修完再 push ===" -f $script:Failed)
    exit 1
}

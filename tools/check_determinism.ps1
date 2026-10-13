# check_determinism.ps1 —— W-00 的验收命令：同参数连跑 N 次，两两比像素 + 比状态指纹
#
#   pwsh -File tools\check_determinism.ps1                  # 4 次 / 300 帧（W-00 验收标准）
#   pwsh -File tools\check_determinism.ps1 -Runs 6 -Seed 7  # 换种子再验
#   pwsh -File tools\check_determinism.ps1 -ShowHud         # 连 HUD 一起比（默认隐藏 HUD，只比世界）
#
# 退出码：0 = 可复现（两两逐像素完全一致且状态指纹一致）；非 0 = 不可复现。
#
# ── 为什么不直接复用 verify_all.ps1 的 ④ ──
# ④ 只跑 2 次、且有 0.05% 容差。W-00 的验收要的是**容差 0、4 次、两两全对**，
# 而且要在不一致时报出「第一个分叉的字段」——那是 tools/determinism_check.py 的活。
#
# ── ⚠️ 与 verify_all.ps1 并发跑会互相覆盖 ──
# verify_all.ps1 写 _install\tmp\verify_*.txt 与 art\_raw\_verify_now*.png。
# 本脚本的输出全部落在 _install\tmp\det\（并把子进程 TEMP 也指过去），
# 所以两个人可以同时跑，互不干扰。
#
# 工具链路径**相对项目自身**解析，不写死盘符（AGENTS.md §0）。

param(
    [int]$Runs = 4,
    [int]$Frames = 300,
    [int]$Seed = 424242,
    [double]$Tolerance = 0.0,
    [switch]$ShowHud,
    # ⭐ 战斗场景：开自动瞄准 + 自动射击。
    #    默认局面下第 300 帧 kills=0/bullets=0/hitstop=0 —— 它**不触发 hitstop**，
    #    用它验收 W-00 等于没验（实测：默认局面 4 次里状态指纹全同，只有 0.018% 渲染抖动）。
    [switch]$Combat,
    # ⭐ W-00 的核心用例：在第 N 帧触发一次 hitstop。
    #    旧实现用墙钟计时，"冻结了几帧"随真实耗时浮动 -> 模拟推进量不同；
    #    帧计数实现下，冻结帧数与 sim_time 必须逐次完全一致。
    [int]$HitstopFrame = 0,
    [string]$HitstopLevel = "heavy",
    # ⭐ 顿帧风暴：每 N 帧触发一次 hitstop。单次冻结的墙钟抖动太小，
    #    累积 20+ 次才会把"模拟推进量不同"放大到 sim_time 上，一眼可见。
    [int]$HitstopEvery = 0
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Godot = Join-Path $Root "_install\godot\Godot_v4.7.2-stable_win64_console.exe"
$PyCandidates = @(
    (Join-Path $Root "_install\python\python.exe"),
    (Join-Path $Root "_install\dependencies\python\python.exe"),
    "$env:LOCALAPPDATA\dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe",
    "C:\Users\xxx\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
)
$Py = $null
foreach ($c in $PyCandidates) { if (Test-Path $c) { $Py = $c; break } }

if (-not (Test-Path $Godot)) { Write-Host "❌ 找不到 Godot：$Godot" -ForegroundColor Red; exit 2 }
if ($Py -eq $null) { Write-Host "❌ 找不到 Python" -ForegroundColor Red; exit 2 }

$OutDir = Join-Path $Root "_install\tmp\det"
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
# 子进程 TEMP 也放这里：不碰 verify_all.ps1 用的 _install\tmp\verify_*.txt
$env:TMP = Join-Path $OutDir "tmp"
$env:TEMP = $env:TMP
New-Item -ItemType Directory -Force -Path $env:TMP | Out-Null
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Write-Host ""
Write-Host "W-00 复现性检查：$Runs 次 / 第 $Frames 帧 / 种子 $Seed / 容差 $Tolerance%" -ForegroundColor Cyan
Write-Host "输出目录：$OutDir"

$ok = $true
$prefix = if ($HitstopEvery -gt 0) { "storm" } elseif ($HitstopFrame -gt 0) { "hs$HitstopFrame" } elseif ($Combat) { "combat" } else { "run" }
for ($i = 1; $i -le $Runs; $i++) {
    $shotRel = "res://_install/tmp/det/${prefix}_$i.png"
    $log = Join-Path $OutDir "${prefix}_$i.log"
    # ⚠️ 用数组 + `@extra` 展开：把 "--a 1 --b 2" 塞进**一个字符串**传给原生命令时，
    #    PowerShell 不会替你拆词，Godot 会把它当成**一个**参数（实测踩过：
    #    --hitstop-frame 从来没生效，而日志里看不出任何错）。
    $extra = @()
    $extra += $(if ($ShowHud) { "--show-hud" } else { "--hide-hud" })
    if ($Combat) { $extra += "--combat" }
    if ($HitstopFrame -gt 0) {
        $extra += @("--hitstop-frame", "$HitstopFrame", "--hitstop-level", $HitstopLevel)
    }
    if ($HitstopEvery -gt 0) {
        $extra += @("--hitstop-every", "$HitstopEvery", "--hitstop-level", $HitstopLevel)
    }
    # ⚠️ 用 Set-Content -Encoding UTF8 而不是 `*>`：
    #    PS 5.1 的 `*>` 默认写 UTF-16LE，python 侧读不到 PROBE_STATE（实测踩过）。
    & $Godot --path $Root --fixed-fps 60 --rendering-driver opengl3 `
        --rendering-method gl_compatibility --resolution 1280x720 `
        --script "res://tools/determinism_probe.gd" -- `
        --seed $Seed --frames $Frames @extra --out $shotRel 2>&1 |
        ForEach-Object { $_.ToString() } | Set-Content -Path $log -Encoding UTF8
    $code = $LASTEXITCODE
    $stateLine = (Select-String -Path $log -Pattern "PROBE_STATE" | Select-Object -Last 1).Line
    if ($code -ne 0 -or $stateLine -eq $null) {
        Write-Host "  ❌ ${prefix}_$i 失败（退出码 $code）—— 日志：$log" -ForegroundColor Red
        Select-String -Path $log -Pattern "PROBE_ERROR|SCRIPT ERROR|Parse Error" |
            Select-Object -First 5 | ForEach-Object { Write-Host "     $($_.Line.Trim())" }
        $ok = $false
    } else {
        Write-Host "  · ${prefix}_$i 完成（退出码 0）" -ForegroundColor DarkGray
    }
}

if (-not $ok) { Write-Host "❌ 有运行失败，判定中止" -ForegroundColor Red; exit 1 }

Write-Host ""
& $Py "tools\determinism_check.py" --dir $OutDir --runs $Runs --prefix $prefix --tolerance $Tolerance
$check = $LASTEXITCODE
Write-Host ""
if ($check -ne 0) {
    Write-Host "❌ W-00 验收未通过（退出码 $check）" -ForegroundColor Red
    exit $check
}
Write-Host "✅ W-00 验收通过：同参数 $Runs 次运行，两两逐像素完全一致。" -ForegroundColor Green
exit 0

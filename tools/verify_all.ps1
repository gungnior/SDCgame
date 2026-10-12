# verify_all.ps1 —— 本项目的**唯一验收命令**
#
# ┌──────────────────────────────────────────────────────────────┐
# │ 任何 agent（DSH 的 Lead/teammate、WorkBuddy、或者人）           │
# │ 在宣称「做完了」之前，**必须跑这一条命令**，并贴出它的输出。      │
# │ 退出码 0 = 可以交付；非 0 = 不许交付。                          │
# └──────────────────────────────────────────────────────────────┘
#
# 为什么要有它：
#   多 agent 协作最大的风险不是写不出代码，是**"done" 的定义不一致** ——
#   A 觉得跑过了、B 觉得没跑，最后谁都不知道能不能交。
#   把验收固化成**一条命令 + 一个退出码**，这件事就不需要信任、只需要执行。
#
# 用法：
#   pwsh -File tools\verify_all.ps1                 # 全量（含像素对比，约 1 分钟）
#   pwsh -File tools\verify_all.ps1 -Fast           # 跳过像素对比（改纯逻辑时用）
#   pwsh -File tools\verify_all.ps1 -UpdateBaseline # 有意改了画面后重设基线
#
# 各项是什么：
#   ① 单元测试     799 项断言（test/suites/*.gd，headless，秒级）
#   ② 集成验证     test/pc_verify.tscn 51 项（真的实例化游戏场景）
#   ③ 数据契约     tools/validate_data.py（JSON schema 与跨表引用）
#   ④ 像素基线     固定种子 + 固定 delta 截图，与 art/_raw/_baseline.png 逐像素比对
#                  —— 这是唯一能抓住"模拟/渲染行为被悄悄改动"的检查

param(
    [switch]$Fast,
    [switch]$UpdateBaseline
)

# ⚠️ 这里**故意不用** $ErrorActionPreference = "Stop"。
#    Godot 每次启动都会往 stderr 写两条无害提示
#    （`Failed to open log file: user://logs/godot.log`、
#      `Failed to read the root certificate store.`）——
#    Stop 模式会把它们当致命错误直接中断脚本（实测踩过）。
#    驱动原生命令的正确姿势是：**看退出码**，不看 stderr 有没有内容。
$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

$Godot = "D:\aaaaadsh\_install\godot\Godot_v4.7.2-stable_win64_console.exe"
$Py = "C:\Users\xxx\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
$env:TMP = "D:\aaaaadsh\_install\tmp"
$env:TEMP = "D:\aaaaadsh\_install\tmp"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 像素基线的固定参数 —— **改这里等于改验收标准，要单独说明理由**
$BASELINE = "art\_raw\_baseline.png"
$SEED = 424242
$FRAMES = 300

$results = @()
$fatal = $false

function Section($n, $title) {
    Write-Host ""
    Write-Host "── $n $title " -NoNewline
    Write-Host ("─" * [Math]::Max(0, 60 - $title.Length)) -ForegroundColor DarkGray
}

function Record($name, $ok, $detail) {
    $script:results += [pscustomobject]@{ 项 = $name; 结果 = $(if ($ok) { "通过" } else { "失败" }); 详情 = $detail }
    if (-not $ok) { $script:fatal = $true }
    $color = if ($ok) { "Green" } else { "Red" }
    Write-Host ("  {0,-6} {1}" -f $(if ($ok) { "✅" } else { "❌" }), $detail) -ForegroundColor $color
}

if (-not (Test-Path $Godot)) { Write-Host "❌ 找不到 Godot: $Godot" -ForegroundColor Red; exit 2 }

# ── 预热导入（避免首次运行把 import 警告算成失败）──
& $Godot --headless --path $Root --import *> $null

# ═══════════════ ① 单元测试 ═══════════════
Section "①" "单元测试（799 项断言）"
$out = Join-Path $env:TEMP "verify_unit.txt"
& $Godot --headless --path $Root --script "res://test/run_tests.gd" *> $out
$unitExit = $LASTEXITCODE
$unitLine = (Select-String -Path $out -Pattern "通过：|失败：" | Select-Object -Last 1).Line
Record "单元测试" ($unitExit -eq 0) "$unitLine（退出码 $unitExit）"
if ($unitExit -ne 0) {
    Write-Host "  ── 失败明细 ──" -ForegroundColor Yellow
    Select-String -Path $out -Pattern "FAIL" | Select-Object -First 20 | ForEach-Object { Write-Host "     $($_.Line.Trim())" }
}

# ═══════════════ ② 集成验证 ═══════════════
Section "②" "集成验证（真的实例化游戏场景）"
$out2 = Join-Path $env:TEMP "verify_pc.txt"
& $Godot --headless --path $Root "res://test/pc_verify.tscn" *> $out2
$pcExit = $LASTEXITCODE
$pcLine = (Select-String -Path $out2 -Pattern "PC 端验证" | Select-Object -Last 1).Line
Record "集成验证" ($pcExit -eq 0) "$pcLine（退出码 $pcExit）"
if ($pcExit -ne 0) {
    Select-String -Path $out2 -Pattern "FAIL|   - " | Select-Object -First 20 | ForEach-Object { Write-Host "     $($_.Line.Trim())" }
}

# ═══════════════ ③ 数据契约 ═══════════════
Section "③" "数据契约（JSON schema + 跨表引用）"
$out3 = Join-Path $env:TEMP "verify_data.txt"
& $Py "tools\validate_data.py" *> $out3
$dataExit = $LASTEXITCODE
$dataLine = (Get-Content $out3 -Encoding UTF8 | Select-Object -Last 1)
Record "数据契约" ($dataExit -eq 0) "$dataLine"

# ═══════════════ ④ 像素基线 ═══════════════
if ($Fast) {
    Section "④" "像素基线（-Fast 已跳过）"
    Write-Host "  ⏭  跳过（只在改纯逻辑时用；改画面/模拟必须全量跑）" -ForegroundColor DarkGray
} else {
    Section "④" "像素基线（固定种子 $SEED / 第 $FRAMES 帧）"
    $shot = "art\_raw\_verify_now.png"
    & $Godot --path $Root --fixed-fps 60 --rendering-driver opengl3 --rendering-method gl_compatibility `
        --resolution 1280x720 --script "res://test/screenshot.gd" -- `
        --seed $SEED --frames $FRAMES --hide-hud --out "res://$($shot -replace '\\','/')" *> $null

    if ($UpdateBaseline) {
        Copy-Item $shot $BASELINE -Force
        Record "像素基线" $true "已重设基线 -> $BASELINE"
    } elseif (-not (Test-Path $BASELINE)) {
        Copy-Item $shot $BASELINE -Force
        Record "像素基线" $true "首次运行，已建立基线 -> $BASELINE"
    } else {
        # 比较逻辑在 tools/compare_images.py 里（独立文件，可手测、不依赖 PowerShell）
        #
        # ⚠️ 先说清楚为什么不用 `ImageChops.difference(...).getbbox()`：
        #    PIL 的 getbbox() 在 **RGBA** 图上以 **alpha 通道**当"非零"掩码，
        #    而截图完全不透明 -> 差值图 alpha 恒为 0 -> 它报「没有差异」。
        #    实测踩到过：玩家从蓝改红（66926 像素真的变了）仍然报一致。
        $diff = & $Py "tools\compare_images.py" $BASELINE $shot 2>&1
        $code = $LASTEXITCODE
        $diff = ($diff | Out-String).Trim()
        $ok = ($code -eq 0)
        Record "像素基线" $ok "与基线比对：$diff"
        if (-not $ok) {
            Write-Host "     ⚠️ 画面/模拟行为变了。" -ForegroundColor Yellow
            Write-Host "        · 如果这是**有意的**改动 -> 复核截图后跑 -UpdateBaseline" -ForegroundColor Yellow
            Write-Host "        · 如果不是 -> 你引入了一个回归" -ForegroundColor Yellow
        }
    }
}

# ═══════════════ 汇总 ═══════════════
Write-Host ""
Write-Host ("═" * 64) -ForegroundColor DarkGray
$results | Format-Table -AutoSize | Out-String | Write-Host
if ($fatal) {
    Write-Host "❌ 验收失败 —— 不许交付。" -ForegroundColor Red
    Write-Host "   修好之后重跑本命令；不要只跑其中一项就说"过了"。" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ 全部通过 —— 可以交付。" -ForegroundColor Green
    exit 0
}

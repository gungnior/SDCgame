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
#   ④ 像素基线     固定种子 + 固定 delta 截图，与 art/_raw/_baseline.png 比对
#
# ⚠️⚠️ ④ 是**咨询性**的，默认**不会**让验收失败 —— 加 -Strict 才当门槛。
#
#    为什么降级：实测这局游戏**运行期本质不确定**。
#    同种子同参数连跑 4 次，第 300 帧两两比较：
#        A 组 5/5 对不一致、B 组 3/5 对不一致
#        （第 30 帧还是一致的，第 60 帧起分叉，到第 300 帧放大到 2~7%）
#    原因是「手感」用了**真实时钟**：feel.gd 的 hitstop 靠
#    `Time.get_ticks_msec()` 把 `Engine.time_scale` 压到 0 ——
#    而 time_scale=0 时 delta 也是 0，游戏**没法用模拟时间给自己计时**，
#    只能用真实时钟。于是停顿帧数随真实耗时浮动 -> 模拟推进量不同
#    -> 混沌放大。
#
#    结论：**像素基线不能当回归门**。会飘的门比没有门更糟（它训练人忽略失败）。
#    真正的回归保障是 ①②③ + 「同一构建连跑两次自身比对」。
#
#    ⚠️ 同时纠正一个早先的说法：拆分 raid_scene.gd 时我用 1v1 截图对比
#       声称过「逐像素完全一致」。那些对比**当时确实通过了**，但在这个
#       随机性面前，**单次对比不构成证据**。
#       唯一可靠的那条是**地图烘焙**：它用的是确定性单测
#       （RaidMapBaker 输出 vs WhiteboxPainter.paint()，3 个种子差异均为 0），
#       不依赖任何运行期时序。

param(
    [switch]$Fast,
    [switch]$UpdateBaseline,
    # 把 ④ 像素基线也当门槛（只在明确知道环境稳定时用）
    [switch]$Strict
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

# ─────────────────────────────────────────────────────────────
# ⭐ 工具链路径**全部相对项目自身**解析，不写死盘符。
#
# 为什么：这个工作区是给「人 + DSH + WorkBuddy」共用的。
# 写死 `D:\AAAASDC\...` 的话，任何人把仓库克隆/移动到别处，验收就全废。
# 现在无论项目在哪个盘、哪个目录，只要 `_install/` 跟着走就能跑。
#
# 顺序：① 先找项目内的 _install/（自包含，推荐）
#       ② 找不到就退回环境里已知的 Python（只影响 Python，Godot 没有回退）
# ─────────────────────────────────────────────────────────────
$Godot = Join-Path $Root "_install\godot\Godot_v4.7.2-stable_win64_console.exe"

# Python 优先用项目内的（如果打包进来了），否则用宿主环境那个
$PyCandidates = @(
    (Join-Path $Root "_install\python\python.exe"),
    (Join-Path $Root "_install\dependencies\python\python.exe"),
    "$env:LOCALAPPDATA\dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe",
    "C:\Users\xxx\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
)
$Py = $null
foreach ($c in $PyCandidates) { if (Test-Path $c) { $Py = $c; break } }

# TEMP 也放项目内，避免污染系统临时目录（并保证多次运行互不干扰）
$TmpDir = Join-Path $Root "_install\tmp"
if (-not (Test-Path $TmpDir)) { New-Item -ItemType Directory -Force -Path $TmpDir | Out-Null }
$env:TMP = $TmpDir
$env:TEMP = $TmpDir
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not (Test-Path $Godot)) {
    Write-Host "❌ 找不到 Godot：$Godot" -ForegroundColor Red
    Write-Host "   这个项目假设 _install/godot/ 跟着仓库走。请确认它没被 .gitignore 之类排除掉。" -ForegroundColor Red
    exit 2
}
if ($Py -eq $null) {
    Write-Host "❌ 找不到 Python。试过：" -ForegroundColor Red
    $PyCandidates | ForEach-Object { Write-Host "     $_" -ForegroundColor Red }
    exit 2
}

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

# ═══════════════ ④ 像素基线（咨询性；-Strict 才当门槛）═══════════════
if ($Fast) {
    Section "④" "像素基线（-Fast 已跳过）"
    Write-Host "  ⏭  跳过" -ForegroundColor DarkGray
} else {
    Section "④" "像素基线（咨询性 —— 见脚本开头的说明）"
    $shot = "art\_raw\_verify_now.png"
    & $Godot --path $Root --fixed-fps 60 --rendering-driver opengl3 --rendering-method gl_compatibility `
        --resolution 1280x720 --script "res://test/screenshot.gd" -- `
        --seed $SEED --frames $FRAMES --hide-hud --out "res://$($shot -replace '\\','/')" *> $null

    # ⭐ 先做**自身复现性检查**：同一构建连跑两次，看这个环境稳不稳。
    #    这比"和基线比"更有意义 —— 它直接测出运行期随机性有多大。
    $shot2 = "art\_raw\_verify_now2.png"
    & $Godot --path $Root --fixed-fps 60 --rendering-driver opengl3 --rendering-method gl_compatibility `
        --resolution 1280x720 --script "res://test/screenshot.gd" -- `
        --seed $SEED --frames $FRAMES --hide-hud --out "res://$($shot2 -replace '\\','/')" *> $null
    # ⚠️⚠️ 2026-10-13：**截图没产出 ≠ 首次运行**。
    #    实测踩过：art\_raw\ 被 .gitignore 排除、克隆里根本不存在，
    #    而 Image.save_png() 不会自建父目录 -> 静默失败（err 7）。
    #    旧脚本接着把"找不到基线"读成"首次运行，已建立基线"，
    #    于是报出一个**看着通过、其实什么都没测**的结果（连续两轮 ④ 都是这么绿的）。
    #    现在：先判定图在不在；不在就判【无效】—— ④ 依然**不是门槛**（咨询性），
    #    但它**不许再说自己通过了**。
    $shotMissing = -not ((Test-Path -LiteralPath $shot) -and (Test-Path -LiteralPath $shot2))
    if ($shotMissing) {
        Write-Host "  · 自身复现性：截图未产出，无法比对" -ForegroundColor Yellow
        Write-Host "    截图目标：$shot / $shot2" -ForegroundColor Yellow
        Write-Host "    实测原因：目标目录被 .gitignore 排除（克隆里不存在），且 Godot 的 save_png 不会自建父目录。" -ForegroundColor Yellow
        Write-Host "    修法：New-Item -ItemType Directory -Force (Split-Path '$BASELINE' -Parent)，然后重跑本命令。" -ForegroundColor Yellow
    } else {
        $selfDiff = (& $Py "tools\compare_images.py" $shot $shot2 --tolerance 0 2>&1 | Out-String).Trim()
        $selfOk = ($LASTEXITCODE -eq 0)
        if ($selfOk) {
            Write-Host "  · 自身复现性：同构建两次截图完全一致（本环境稳定）" -ForegroundColor Green
        } else {
            Write-Host "  · 自身复现性：两次截图不一致 -> $selfDiff" -ForegroundColor Yellow
            Write-Host "    说明这局游戏**运行期本质不确定**（手感用真实时钟），像素比对不可作为回归门。" -ForegroundColor Yellow
        }
    }

    if ($shotMissing) {
        $results += [pscustomobject]@{ 项 = "像素基线"; 结果 = "无效"; 详情 = "截图未产出（目录缺失 / save_png 不自建父目录）" }
    } elseif ($UpdateBaseline) {
        Copy-Item $shot $BASELINE -Force
        Record "像素基线" $true "已重设基线 -> $BASELINE"
    } elseif (-not (Test-Path $BASELINE)) {
        Copy-Item $shot $BASELINE -Force
        Record "像素基线" $true "首次运行，已建立基线 -> $BASELINE"
    } else {
        # 比较逻辑在 tools/compare_images.py 里（独立文件，可手测、不依赖 PowerShell）
        #
        # ⚠️ 为什么不用 `ImageChops.difference(...).getbbox()`：
        #    PIL 的 getbbox() 在 **RGBA** 图上以 **alpha 通道**当"非零"掩码，
        #    而截图完全不透明 -> 差值图 alpha 恒为 0 -> 它报「没有差异」。
        #    实测踩到过：玩家从蓝改红（66926 像素真的变了）仍然报一致。
        $diff = & $Py "tools\compare_images.py" $BASELINE $shot 2>&1
        $code = $LASTEXITCODE
        $diff = ($diff | Out-String).Trim()
        $ok = ($code -eq 0)
        if ($ok) {
            Record "像素基线" $true "与基线一致：$diff"
        } elseif ($Strict) {
            Record "像素基线" $false "与基线不一致：$diff"
            Write-Host "     （-Strict：把它当门槛）" -ForegroundColor Yellow
        } else {
            # 咨询性：只报告，不让验收失败。
            # 理由见脚本开头 —— 这局游戏运行期本质不确定，硬门槛会误报。
            $results += [pscustomobject]@{ 项 = "像素基线"; 结果 = "参考"; 详情 = $diff }
            Write-Host "  ℹ️    与基线不一致（咨询性，不影响验收）：$diff" -ForegroundColor DarkYellow
        }
    }
}

# ═══════════════ 汇总 ═══════════════
Write-Host ""
Write-Host ("═" * 64) -ForegroundColor DarkGray
$results | Format-Table -AutoSize | Out-String | Write-Host
if ($fatal) {
    Write-Host "❌ 验收失败 —— 不许交付。" -ForegroundColor Red
    Write-Host "   修好之后重跑本命令；不要只跑其中一项就说'过了'。" -ForegroundColor Red
    exit 1
} else {
    Write-Host "✅ 通过（①②③ 是门槛；④ 像素基线仅供参考）—— 可以交付。" -ForegroundColor Green
    exit 0
}

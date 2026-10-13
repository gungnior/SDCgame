# android_verify.ps1 —— W-01 安卓真机/模拟器验证（一键）
#
# 作用：把 W-01 ①「安卓 user:// 存档」从"PC 侧推断"变成"真机实证"。
#   ① 确认有设备连着（否则提示怎么连）；
#   ② 安装 arm64 APK；
#   ③ 启动 app，抓 logcat，看有没有崩溃；
#   ④ 用 run-as 看 user://(=/data/data/<pkg>/files) 是否可写、存档是否落盘。
#
# ⚠️ 安卓 user:// 只能在这台设备上验；PC 上 SaveManager 走的是 user://(可写时)
#    或可移植回退，两条路在 PC 都可能命中 user://，所以必须真机确认。
#
# 用法：
#   pwsh -File tools\android_verify.ps1                       # 默认包/默认 APK
#   pwsh -File tools\android_verify.ps1 -Apk build\soudache-w01.apk
#   pwsh -File tools\android_verify.ps1 -Adb "C:\...\platform-tools\adb.exe"
#
# 前置（MIUI/红米常见，缺一不可）：
#   · 开发者选项 → USB 调试：开
#   · 开发者选项 → **USB 安装**（Install via USB）：开   ← 不开则 adb install 失败
#   · 手机解锁 + 点「允许 USB 调试」授权弹窗
#
# 完整"存档持久化"验证需手动玩一局（见末尾 STEPS 注释）。

param(
    [string]$Apk = "build\soudache-w01.apk",
    [string]$Package = "com.aaaaadsh.soudache",
    [string]$Adb = "",
    [int]$WaitSec = 6
)

$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

# ── 解析 adb：优先参数 → PATH → 已知 SDK 位置 ──
if ($Adb -eq "") {
    $cmd = Get-Command adb -ErrorAction SilentlyContinue
    if ($cmd) { $Adb = $cmd.Source }
    else {
        $cand = Join-Path $env:LOCALAPPDATA "Android\Sdk\platform-tools\adb.exe"
        if (Test-Path $cand) { $Adb = $cand }
    }
}
if ($Adb -eq "" -or -not (Test-Path $Adb)) {
    Write-Host "❌ 找不到 adb。用 -Adb 指定 platform-tools\adb.exe 路径。" -ForegroundColor Red
    exit 2
}

# ── ① 设备检查 ──
$devLines = & $Adb devices | Select-Object -Skip 1 | Where-Object { $_ -match "\S" }
$ready = $devLines | Where-Object { $_ -match "\bdevice$" }
if (-not $ready) {
    Write-Host "❌ 没有已授权的设备。当前：" -ForegroundColor Red
    $devLines | ForEach-Object { Write-Host "   $_" }
    Write-Host @"
   请：
     1) USB 连接手机，解锁屏幕；
     2) 开发者选项 → USB 调试：开；
     3) 开发者选项 → USB 安装（Install via USB）：开；   ← MIUI 装 APK 必须
     4) 在手机上点「允许 USB 调试」授权弹窗；
     5) 重跑本脚本。
"@ -ForegroundColor Yellow
    exit 2
}
$serial = ($ready | Select-Object -First 1).ToString().Split()[0]
Write-Host "✅ 设备已连接：$serial" -ForegroundColor Green

# ── ② 安装 ──
if (-not (Test-Path $Apk)) {
    Write-Host "❌ 找不到 APK：$Apk（先跑 godot --export-debug Android）" -ForegroundColor Red
    exit 2
}
Write-Host "── 安装 $Apk ──"
& $Adb -s $serial install -r -t "$Apk" 2>&1 | ForEach-Object { Write-Host "   $_" }
if ($LASTEXITCODE -ne 0) {
    Write-Host "❌ 安装失败。若错误为空/INSTALL_FAILED_*，多半是没开「USB 安装」权限。" -ForegroundColor Red
    exit 3
}

# ── ③ 启动 + 抓 logcat ──
Write-Host "── 启动 app ──"
& $Adb -s $serial logcat -c 2>$null
& $Adb -s $serial shell monkey -p $Package -c android.intent.category.LAUNCHER 1 2>&1 | Select-Object -Last 1 | ForEach-Object { Write-Host "   $_" }
Write-Host "── 等待 $WaitSec 秒后抓 logcat ──"
Start-Sleep -Seconds $WaitSec

$logFile = Join-Path $Root "_install\tmp\android_logcat.txt"
& $Adb -s $serial logcat -d > $logFile 2>&1
$crash = Select-String -Path $logFile -Pattern "FATAL|AndroidRuntime|$Package.*Exception|have you declared" -ErrorAction SilentlyContinue
if ($crash) {
    Write-Host "⚠️ logcat 有崩溃/异常迹象：" -ForegroundColor Yellow
    $crash | Select-Object -First 10 | ForEach-Object { Write-Host "   $($_.Line.Trim())" }
} else {
    Write-Host "✅ 启动后 logcat 未见崩溃（详细见 $logFile）" -ForegroundColor Green
}

# ── ④ user:// 可写性 + 存档落盘 ──
# 安卓 user:// 映射到 /data/data/<pkg>/files（debug 包可用 run-as 查看）
Write-Host "── 检查 user://(files/) 内容 ──"
$files = & $Adb -s $serial shell "run-as $Package ls -R files 2>/dev/null" 2>&1
if ($files -match "No such file|run-as:") {
    Write-Host "   （run-as 不可用——可能不是 debug 包，或设备限制。改用下方手动步骤。）" -ForegroundColor DarkYellow
} else {
    $files | ForEach-Object { Write-Host "   $_" }
}
$hasSave = ($files | Out-String) -match "soudache_save\.json"
if ($hasSave) {
    Write-Host "✅ user:// 可写，且存档 soudache_save.json 已落盘（W-01 ① 真机通过）" -ForegroundColor Green
} else {
    Write-Host "ℹ️ 尚未见 soudache_save.json —— 需玩一局（搜刮→撤离/死亡）触发存档后再查。" -ForegroundColor Cyan
}

Write-Host @"

── 手动补全"存档持久化"（W-01 ① 完全通过需这一步）──
   STEPS：
   1) 在手机上玩一局：进图 → 到撤离点撤离（或死亡结算）；
   2) 回桌面/藏身处，设置里改一个开关（触发 settings 存档）；
   3) 重跑：adb shell run-as $Package ls -l files/
      —— 应看到 soudache_save.json；
   4) 强制停止并重启 app：adb shell am force-stop $Package
      —— 钱数/设置应保持（证明 user:// 真的持久化）。
"@ -ForegroundColor Cyan
exit 0

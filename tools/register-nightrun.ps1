# register-nightrun.ps1 —— 把夜间跑器注册进 Windows 任务计划程序
#
# 用法：
#   .\tools\register-nightrun.ps1              # 注册（每天 00:30）
#   .\tools\register-nightrun.ps1 -At 19:00,00:30   # 自定义时间（可多个）
#   .\tools\register-nightrun.ps1 -Unregister  # 卸载
#   .\tools\register-nightrun.ps1 -Show        # 查看当前注册状态
#
# 说明：脚本本身会在启动时检查 DeepSeek 时段，高峰时自动跳过（除非加 -Force）。
#       所以这里可以放心多注册几个时间点。

param(
    [string[]]$At = @('00:30'),
    [string]$TaskName = 'DSH-NightRun-搜打撤',
    [switch]$Unregister,
    [switch]$Show,
    [switch]$Force,
    [int]$MaxTasks = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root       = Split-Path -Parent $PSScriptRoot
$RunnerPath = Join-Path $PSScriptRoot 'nightrun.ps1'

if ($Show) {
    $t = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    if (-not $t) { Write-Host "未注册：$TaskName" -ForegroundColor Yellow; exit 0 }
    Write-Host "任务：$TaskName" -ForegroundColor Cyan
    Write-Host "  状态：$($t.State)"
    $t.Triggers | ForEach-Object { Write-Host "  触发：$($_.StartBoundary)" }
    Write-Host "  动作：$($t.Actions[0].Execute) $($t.Actions[0].Arguments)"
    Write-Host "`n最近运行结果：" -ForegroundColor Cyan
    Get-ScheduledTaskInfo -TaskName $TaskName |
        Select-Object LastRunTime, LastTaskResult, NextRunTime | Format-List
    exit 0
}

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "已卸载：$TaskName" -ForegroundColor Green
    } else {
        Write-Host "本来就没注册：$TaskName" -ForegroundColor Yellow
    }
    exit 0
}

if (-not (Test-Path $RunnerPath)) { throw "找不到跑器：$RunnerPath" }

# 找 pwsh
$pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
if (-not $pwsh) { throw "找不到 pwsh（PowerShell 7）" }

# 参数（含 -Force 时透传）
$runnerArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`" -MaxTasks $MaxTasks"
if ($Force) { $runnerArgs += ' -Force' }

$action = New-ScheduledTaskAction -Execute $pwsh -Argument $runnerArgs -WorkingDirectory $Root

$triggers = @()
foreach ($t in $At) {
    $triggers += New-ScheduledTaskTrigger -Daily -At $t
}

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 3) `
    -MultipleInstances IgnoreNew

# 已存在则先删（保证幂等）
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Description "在 DeepSeek 空闲时段（半价）执行 tasks/queue.json 的 pending 任务。仅跑有自动验收的机械任务。" | Out-Null

Write-Host "✅ 已注册：$TaskName" -ForegroundColor Green
Write-Host "   触发时间：$($At -join ', ')"
Write-Host "   跑器：$RunnerPath"
Write-Host "   工作目录：$Root"
Write-Host "   参数：$runnerArgs"
Write-Host ""
Write-Host "提示：脚本启动时会自行检查 DeepSeek 时段，高峰时段自动跳过。" -ForegroundColor DarkGray
Write-Host "     手动试跑： pwsh -NoProfile -File `"$RunnerPath`" -DryRun" -ForegroundColor DarkGray

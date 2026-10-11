# register-nightrun.ps1 -- register the night runner with Windows Task Scheduler
#
# Usage:
#   .\tools\register-nightrun.ps1                   # register (daily at 00:30)
#   .\tools\register-nightrun.ps1 -At 19:00,00:30   # custom times (multiple allowed)
#   .\tools\register-nightrun.ps1 -Unregister       # remove
#   .\tools\register-nightrun.ps1 -Show             # show registration status
#
# The runner re-checks the DeepSeek price phase itself and skips during peak
# hours (unless -Force), so registering several times is safe.
#
# NOTE: ASCII-only on purpose (see offpeak.ps1 header for why).

param(
    [string[]]$At = @('00:30'),
    [string]$TaskName = 'DSH-NightRun',
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
    if (-not $t) { Write-Host "not registered: $TaskName" -ForegroundColor Yellow; exit 0 }
    Write-Host "task: $TaskName" -ForegroundColor Cyan
    Write-Host "  state: $($t.State)"
    $t.Triggers | ForEach-Object { Write-Host "  trigger: $($_.StartBoundary)" }
    Write-Host "  action: $($t.Actions[0].Execute) $($t.Actions[0].Arguments)"
    Write-Host "`nlast run:" -ForegroundColor Cyan
    Get-ScheduledTaskInfo -TaskName $TaskName |
        Select-Object LastRunTime, LastTaskResult, NextRunTime | Format-List
    exit 0
}

if ($Unregister) {
    if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
        Write-Host "unregistered: $TaskName" -ForegroundColor Green
    } else {
        Write-Host "was not registered: $TaskName" -ForegroundColor Yellow
    }
    exit 0
}

if (-not (Test-Path $RunnerPath)) { throw "runner not found: $RunnerPath" }

# Interpreter-agnostic: PS7 -> pwsh.exe, PS5.1 -> powershell.exe
$PSHostExe = if ($PSVersionTable.PSEdition -eq 'Core') {
    Join-Path $PSHOME 'pwsh.exe'
} else {
    Join-Path $PSHOME 'powershell.exe'
}
if (-not (Test-Path $PSHostExe)) { throw "PowerShell host not found: $PSHostExe" }

$runnerArgs = "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`" -MaxTasks $MaxTasks"
if ($Force) { $runnerArgs += ' -Force' }

$action = New-ScheduledTaskAction -Execute $PSHostExe -Argument $runnerArgs -WorkingDirectory $Root

$triggers = @()
foreach ($t in $At) { $triggers += New-ScheduledTaskTrigger -Daily -At $t }

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 3) `
    -MultipleInstances IgnoreNew

# idempotent: remove any existing registration first
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $triggers `
    -Settings $settings `
    -Description "Run pending tasks from tasks/queue.json during DeepSeek off-peak hours (half price). Only mechanical tasks with automated acceptance checks." | Out-Null

Write-Host "OK registered: $TaskName" -ForegroundColor Green
Write-Host "  triggers:   $($At -join ', ')"
Write-Host "  runner:     $RunnerPath"
Write-Host "  workingdir: $Root"
Write-Host "  args:       $runnerArgs"
Write-Host ""
Write-Host "The runner re-checks the price phase and skips during peak hours." -ForegroundColor DarkGray
Write-Host "Dry run:  powershell -NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`" -DryRun" -ForegroundColor DarkGray

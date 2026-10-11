# nightrun.ps1 -- off-peak batch runner
#
# Runs pending tasks from tasks/queue.json during DeepSeek's off-peak window
# (half price). Only tasks whose status is "pending" are picked up.
#
# DESIGN RULE: only mechanical tasks WITH AN AUTOMATED ACCEPTANCE CHECK belong
# here. Core gameplay, feel tuning, and architecture decisions must never be
# queued -- those require a human present.
#
# Each task that fails acceptance is rolled back and the queue STOPS immediately
# (no cascading), so one bad output cannot multiply into many.
#
# Usage:
#   .\tools\nightrun.ps1                  # phase check, run up to 3 tasks
#   .\tools\nightrun.ps1 -DryRun          # show what would happen, change nothing
#   .\tools\nightrun.ps1 -Force           # run even during peak hours
#   .\tools\nightrun.ps1 -Force -MaxTasks 1 -KeepGoing
#   .\tools\nightrun.ps1 -Status          # show phase + queue status
#
# NOTE: ASCII-only on purpose (see offpeak.ps1 header for why).

param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Status,
    [switch]$KeepGoing,          # continue after a failure (default: stop)
    [int]$MaxTasks = 3,
    [int]$TaskTimeoutMin = 20,
    [switch]$NoCommit,
    [string]$DshPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Interpreter-agnostic
$PSExe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }

$Root      = Split-Path -Parent $PSScriptRoot
$QueuePath = Join-Path $Root 'tasks\queue.json'
$LogDir    = Join-Path $Root '_nightrun'
$Stamp     = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogFile   = Join-Path $LogDir "run-$Stamp.log"

New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

function Log($msg, $color = 'Gray') {
    $line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $msg
    Write-Host $line -ForegroundColor $color
    Add-Content -Path $LogFile -Value $line -Encoding UTF8
}

# ---------- locate dsh ----------
if (-not $DshPath) {
    $guess = Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'
    if (Test-Path $guess) {
        $DshPath = $guess
    } elseif (Get-Command dsh -ErrorAction SilentlyContinue) {
        $DshPath = 'dsh'
    }
}
if (-not $DshPath) { Log "dsh not found; pass -DshPath" 'Red'; exit 2 }
Log "dsh = $DshPath"

# ---------- phase ----------
. (Join-Path $PSScriptRoot 'offpeak.ps1')
$info = Get-DsPhaseInfo

function Show-Status {
    Write-Host ''
    Write-Host (Format-DsPhase) -ForegroundColor $(if ($info.Phase -eq 'offpeak') { 'Green' } else { 'Yellow' })
    Write-Host ("  deepseek-flash output price: CNY {0} / M tokens" -f $info.PriceOutput)
    Write-Host ''
    $q = Get-Content $QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-Host "Task queue:" -ForegroundColor Cyan
    $q.tasks | ForEach-Object {
        $c = switch ($_.status) { 'done' { 'Green' } 'failed' { 'Red' } default { 'Gray' } }
        Write-Host ("  [{0,-8}] {1,-6} {2}" -f $_.status, $_.id, $_.title) -ForegroundColor $c
    }
    Write-Host ''
}

if ($Status) { Show-Status; exit 0 }

# ---------- phase gate ----------
if ($info.Phase -eq 'peak' -and -not $Force) {
    Log "Currently PEAK hours (full price); skipping. $($info.MinutesToSwitch) min until off-peak." 'Yellow'
    Log "Add -Force to run anyway." 'Yellow'
    exit 0
}
if ($info.Phase -eq 'peak' -and $Force) {
    Log "WARNING: peak hours, proceeding because of -Force (full price)." 'Yellow'
} else {
    Log "OK: off-peak window (half price)" 'Green'
}

# ---------- git safety net ----------
$inGit = $false
Push-Location $Root
try {
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) { $inGit = $true }
} catch { }
Pop-Location

if ($inGit) {
    Push-Location $Root
    $dirty = git status --porcelain
    Pop-Location
    if ($dirty -and -not $DryRun) {
        Log "ABORT: working tree is dirty. The rollback net would destroy uncommitted work." 'Red'
        Log "       Commit or stash first. Current changes:" 'Red'
        $dirty | Select-Object -First 10 | ForEach-Object { Log "         $_" 'Red' }
        exit 3
    }
    Log "OK: git tree clean, rollback net armed"
} else {
    Log "WARNING: not a git repo -- a failed task CANNOT be rolled back automatically." 'Yellow'
    if (-not $DryRun) {
        Log "         Run: git init && git add -A && git commit -m 'init'" 'Yellow'
    }
}

# ---------- run ----------
$queue = Get-Content $QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
$pending = @($queue.tasks | Where-Object { $_.status -eq 'pending' } | Select-Object -First $MaxTasks)

if ($pending.Count -eq 0) { Log "No pending tasks. Done." 'Green'; exit 0 }
Log "Processing $($pending.Count) task(s), limit $MaxTasks" 'Cyan'

$ok = 0; $bad = 0
foreach ($task in $pending) {
    Log "-------- $($task.id): $($task.title) --------" 'Cyan'

    if ($DryRun) {
        Log "  [DryRun] would call dsh headless, prompt is $($task.prompt.Length) chars"
        Log "  [DryRun] would verify with: $($task.verify.type)"
        continue
    }

    # 1) call headless
    $promptFile = Join-Path $LogDir "$($task.id).prompt.txt"
    $outFile    = Join-Path $LogDir "$($task.id).out.jsonl"
    $errFile    = Join-Path $LogDir "$($task.id).err.txt"
    Set-Content -Path $promptFile -Value $task.prompt -Encoding UTF8

    $dshArgs = @('--profile', 'headless', '--json', '-')
    Log "  launching dsh headless (timeout ${TaskTimeoutMin} min, prompt via stdin)"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $proc = Start-Process -FilePath $DshPath -ArgumentList $dshArgs `
            -RedirectStandardInput $promptFile `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile `
            -NoNewWindow -PassThru
        $null = $proc | Wait-Process -Timeout ($TaskTimeoutMin * 60) -ErrorAction SilentlyContinue
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Log "  TIMEOUT, process killed" 'Yellow'
        } else {
            Log "  dsh exit code $($proc.ExitCode), took $([int]$sw.Elapsed.TotalSeconds)s"
        }
    } catch {
        Log "  dsh invocation failed: $($_.Exception.Message)" 'Red'
    }
    $sw.Stop()

    # 2) verify
    Log "  verifying: $($task.verify.type)"
    $verifyOut = & $PSExe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'verify.ps1') `
        -QueuePath $QueuePath -TaskId $task.id 2>&1
    $verifyCode = $LASTEXITCODE
    $verifyOut | Select-Object -First 12 | ForEach-Object { Log "    $_" }
    Add-Content -Path $LogFile -Value ($verifyOut -join "`n") -Encoding UTF8

    # 3) record result
    $queueObj = Get-Content $QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $entry = $queueObj.tasks | Where-Object { $_.id -eq $task.id }

    if ($verifyCode -eq 0) {
        $ok++
        Log "  PASS" 'Green'
        $entry.status = 'done'
        $entry.finishedAt = (Get-Date).ToString('s')
        if ($inGit -and -not $NoCommit) {
            Push-Location $Root
            git add -A 2>&1 | Out-Null
            git commit -m "$($task.id): $($task.title)" --quiet 2>&1 | Out-Null
            $c = $LASTEXITCODE
            Pop-Location
            if ($c -eq 0) { Log "  committed $($task.id)" 'Green' } else { Log "  git commit returned $c" 'Yellow' }
        }
    } else {
        $bad++
        Log "  FAIL (exit $verifyCode) -- rolling back" 'Red'
        $entry.status = 'failed'
        $entry.failedAt = (Get-Date).ToString('s')
        $entry.failReason = ($verifyOut | Select-Object -First 3) -join ' / '
        if ($inGit -and -not $NoCommit) {
            Push-Location $Root
            git checkout -- . 2>&1 | Out-Null
            git clean -fd 2>&1 | Out-Null
            Pop-Location
            Log "  rolled back to last commit" 'Yellow'
        }
        Set-Content -Path $QueuePath -Value ($queueObj | ConvertTo-Json -Depth 20) -Encoding UTF8
        if (-not $KeepGoing) {
            Log "STOP: failure halts the queue to avoid cascading errors." 'Red'
            break
        }
        continue
    }
    Set-Content -Path $QueuePath -Value ($queueObj | ConvertTo-Json -Depth 20) -Encoding UTF8
}

Log "-------- summary: $ok ok, $bad failed --------" $(if ($bad -gt 0) { 'Red' } else { 'Green' })
Log "log: $LogFile"
if ($bad -gt 0) { exit 1 } else { exit 0 }

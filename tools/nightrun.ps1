# nightrun.ps1 —— 错峰时段夜间批处理跑器
#
# 在 DeepSeek 空闲时段（半价）自动执行 tasks/queue.json 里 status=pending 的任务。
#
# ⚠️ 设计铁律：只跑【有自动验收命令】的机械任务。核心玩法/手感/架构决策绝不入队。
#    每个任务验收不过就回滚并【立即停止队列】，不级联——避免一个错误放大成一片。
#
# 用法：
#   .\tools\nightrun.ps1                    # 检查时段，跑最多 3 个任务
#   .\tools\nightrun.ps1 -DryRun            # 只显示会做什么，不实际执行
#   .\tools\nightrun.ps1 -Force             # 忽略时段检查（高峰也跑）
#   .\tools\nightrun.ps1 -Force -MaxTasks 1 -KeepGoing
#   .\tools\nightrun.ps1 -Status            # 查看当前时段与任务状态

param(
    [switch]$DryRun,
    [switch]$Force,
    [switch]$Status,
    [switch]$KeepGoing,                    # 失败后继续跑后续任务（默认失败即停）
    [int]$MaxTasks = 3,
    [int]$TaskTimeoutMin = 20,
    [switch]$NoCommit,
    [string]$DshPath = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

# ---------- 定位 dsh ----------
if (-not $DshPath) {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\DeepSeek Harness\resources\runtime\cli\bin\dsh.cmd'),
        'dsh'
    )
    $DshPath = $candidates | Where-Object {
        if ($_ -eq 'dsh') { $null -ne (Get-Command dsh -ErrorAction SilentlyContinue) }
        else { Test-Path $_ }
    } | Select-Object -First 1
}
if (-not $DshPath) { Log "找不到 dsh 可执行文件，请用 -DshPath 指定" 'Red'; exit 2 }
Log "dsh = $DshPath"

# ---------- 时段 ----------
. (Join-Path $PSScriptRoot 'offpeak.ps1')
$info = Get-DsPhaseInfo

function Show-Status {
    Write-Host ''
    Write-Host (Format-DsPhase) -ForegroundColor $(if ($info.Phase -eq 'offpeak') { 'Green' } else { 'Yellow' })
    Write-Host ("  deepseek-flash 输出单价：¥{0}/M token" -f $info.PriceOutput)
    Write-Host ''
    $q = Get-Content $QueuePath -Raw | ConvertFrom-Json
    Write-Host "任务队列：" -ForegroundColor Cyan
    $q.tasks | ForEach-Object {
        $c = switch ($_.status) { 'done' { 'Green' } 'failed' { 'Red' } default { 'Gray' } }
        Write-Host ("  [{0,-8}] {1,-6} {2}" -f $_.status, $_.id, $_.title) -ForegroundColor $c
    }
    Write-Host ''
}

if ($Status) { Show-Status; exit 0 }

# ---------- 时段闸门 ----------
if ($info.Phase -eq 'peak' -and -not $Force) {
    Log "当前为高峰时段（全价），跳过。距空闲还有 $($info.MinutesToSwitch) 分钟。" 'Yellow'
    Log "如确需现在运行，加 -Force。" 'Yellow'
    exit 0
}
if ($info.Phase -eq 'peak' -and $Force) {
    Log "⚠ 高峰时段，但因 -Force 继续运行（全价）。" 'Yellow'
} else {
    Log "✅ 空闲时段（半价）" 'Green'
}

# ---------- git 安全网 ----------
$inGit = $false
try {
    Push-Location $Root
    $null = git rev-parse --is-inside-work-tree 2>$null
    if ($LASTEXITCODE -eq 0) { $inGit = $true }
    Pop-Location
} catch { Pop-Location -ErrorAction SilentlyContinue }

if ($inGit) {
    Push-Location $Root
    $dirty = git status --porcelain
    Pop-Location
    if ($dirty -and -not $DryRun) {
        Log "❌ 工作区不干净，拒绝运行——回滚安全网会毁掉未提交的改动。" 'Red'
        Log "   请先 commit 或 stash。当前改动：" 'Red'
        $dirty | Select-Object -First 10 | ForEach-Object { Log "     $_" 'Red' }
        exit 3
    }
    Log "✅ git 工作区干净，回滚安全网可用"
} else {
    Log "⚠ 不是 git 仓库 —— 任务失败时【无法自动回滚】。" 'Yellow'
    if (-not $DryRun) {
        Log "   建议先执行：git init && git add -A && git commit -m 'init'" 'Yellow'
        Log "   或在确实不需要回滚时加 -NoCommit 继续。" 'Yellow'
    }
}

# ---------- 跑任务 ----------
$queue = Get-Content $QueuePath -Raw | ConvertFrom-Json
$pending = @($queue.tasks | Where-Object { $_.status -eq 'pending' } | Select-Object -First $MaxTasks)

if ($pending.Count -eq 0) { Log "没有 pending 任务，退出。" 'Green'; exit 0 }
Log "本次将处理 $($pending.Count) 个任务（上限 $MaxTasks）" 'Cyan'

$ok = 0; $bad = 0
foreach ($task in $pending) {
    Log "──────── $($task.id)：$($task.title) ────────" 'Cyan'

    if ($DryRun) {
        Log "  [DryRun] 会执行 dsh headless，prompt 长度 $($task.prompt.Length) 字符"
        Log "  [DryRun] 会验收：$($task.verify.type)"
        continue
    }

    # 1) 调用 headless
    $promptFile = Join-Path $LogDir "$($task.id).prompt.txt"
    $outFile    = Join-Path $LogDir "$($task.id).out.jsonl"
    $errFile    = Join-Path $LogDir "$($task.id).err.txt"
    Set-Content -Path $promptFile -Value $task.prompt -Encoding UTF8

    $args = @('--profile', 'headless', '--json', '-')
    Log "  启动 dsh headless（超时 ${TaskTimeoutMin} 分钟，prompt 走 stdin）"
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        $proc = Start-Process -FilePath $DshPath -ArgumentList $args `
            -RedirectStandardInput $promptFile `
            -RedirectStandardOutput $outFile `
            -RedirectStandardError $errFile `
            -NoNewWindow -PassThru
        $null = $proc | Wait-Process -Timeout ($TaskTimeoutMin * 60) -ErrorAction SilentlyContinue
        if (-not $proc.HasExited) {
            Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
            Log "  ⏱ 超时，已终止进程" 'Yellow'
        } else {
            Log "  dsh 退出码 $($proc.ExitCode)，耗时 $([int]$sw.Elapsed.TotalSeconds) 秒"
        }
    } catch {
        Log "  ❌ dsh 调用失败：$($_.Exception.Message)" 'Red'
    }
    $sw.Stop()

    # 2) 验收
    Log "  验收：$($task.verify.type)"
    $verifyOut = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify.ps1') `
        -QueuePath $QueuePath -TaskId $task.id 2>&1
    $verifyCode = $LASTEXITCODE
    $verifyOut | Select-Object -First 12 | ForEach-Object { Log "    $_" }
    Add-Content -Path $LogFile -Value ($verifyOut -join "`n") -Encoding UTF8

    # 3) 结果
    $queueObj = Get-Content $QueuePath -Raw | ConvertFrom-Json
    $entry = $queueObj.tasks | Where-Object { $_.id -eq $task.id }

    if ($verifyCode -eq 0) {
        $ok++
        Log "  ✅ 通过" 'Green'
        $entry.status = 'done'
        $entry.finishedAt = (Get-Date).ToString('s')
        if ($inGit -and -not $NoCommit) {
            Push-Location $Root
            git add -A 2>&1 | Out-Null
            git commit -m "$($task.id): $($task.title)" --quiet 2>&1 | Out-Null
            $c = $LASTEXITCODE
            Pop-Location
            if ($c -eq 0) { Log "  已提交：$($task.id)" 'Green' } else { Log "  ⚠ git commit 返回 $c" 'Yellow' }
        }
    } else {
        $bad++
        Log "  ❌ 验收失败（退出码 $verifyCode）—— 回滚" 'Red'
        $entry.status = 'failed'
        $entry.failedAt = (Get-Date).ToString('s')
        $entry.failReason = ($verifyOut | Select-Object -First 3) -join ' / '
        if ($inGit -and -not $NoCommit) {
            Push-Location $Root
            git checkout -- . 2>&1 | Out-Null
            git clean -fd 2>&1 | Out-Null
            Pop-Location
            Log "  已回滚到上次提交" 'Yellow'
        }
        Set-Content -Path $QueuePath -Value ($queueObj | ConvertTo-Json -Depth 20) -Encoding UTF8
        if (-not $KeepGoing) {
            Log "🛑 失败即停：不再执行后续任务（避免错误级联）。" 'Red'
            break
        }
        continue
    }
    Set-Content -Path $QueuePath -Value ($queueObj | ConvertTo-Json -Depth 20) -Encoding UTF8
}

Log "──────── 汇总：成功 $ok，失败 $bad ────────" $(if ($bad -gt 0) { 'Red' } else { 'Green' })
Log "日志：$LogFile"
if ($bad -gt 0) { exit 1 } else { exit 0 }

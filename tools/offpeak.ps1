# offpeak.ps1 —— DeepSeek 空闲时段判断
#
# 官方规则（https://api-docs.deepseek.com/zh-cn/quick_start/pricing/）：
#   北京时间 周一至周五（不含中国法定节假日）9:00-12:00、14:00-18:00 为高峰时段；
#   其余时段，包括周末及中国法定节假日全天均为空闲时段。
#   空闲时段价格为高峰时段价格的一半。
#
# 用法：
#   . .\tools\offpeak.ps1          # 点源引入，使用下面的函数
#   Get-DsPricePhase               # 返回 "offpeak" / "peak"
#   Get-DsPhaseInfo                # 返回详细对象
#   Test-DsOffPeak                 # 返回 $true / $false

Set-StrictMode -Version Latest

# 中国法定节假日（仅需列出「落在工作日」的日期；周末本来就已是空闲时段）。
# ⚠️ 每年国务院公布后需更新。格式：yyyy-MM-dd
# 该文件不存在时视为空列表（后果：法定节假日当天会被误判为高峰，仅多花几毛钱）。
$script:DsHolidayFile = Join-Path $PSScriptRoot 'cn-holidays.json'

function Get-DsHolidays {
    if (Test-Path $script:DsHolidayFile) {
        try {
            $j = Get-Content $script:DsHolidayFile -Raw | ConvertFrom-Json
            return @($j.holidays)
        } catch {
            Write-Warning "cn-holidays.json 解析失败，按无节假日处理：$($_.Exception.Message)"
            return @()
        }
    }
    return @()
}

# 高峰时段：工作日 09:00-12:00 与 14:00-18:00
$script:DsPeakWindows = @(
    @{ Start = '09:00'; End = '12:00' },
    @{ Start = '14:00'; End = '18:00' }
)

function Get-DsPhaseInfo {
    <#
    .SYNOPSIS
      返回当前 DeepSeek 价格时段信息（按北京时间判定，与机器本地时区无关）。
    #>
    $cn = [System.TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
    $now = [System.TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $cn)
    $dateStr = $now.ToString('yyyy-MM-dd')
    $timeStr = $now.ToString('HH:mm')

    $isWeekend = ($now.DayOfWeek -eq 'Saturday' -or $now.DayOfWeek -eq 'Sunday')
    $isHoliday = (Get-DsHolidays) -contains $dateStr

    $inPeakWindow = $false
    foreach ($w in $script:DsPeakWindows) {
        if ($timeStr -ge $w.Start -and $timeStr -lt $w.End) { $inPeakWindow = $true; break }
    }

    $isPeak = ($inPeakWindow -and -not $isWeekend -and -not $isHoliday)

    # 计算距下次切换的分钟数
    $minutesToSwitch = $null
    if ($isPeak) {
        foreach ($w in $script:DsPeakWindows) {
            if ($timeStr -ge $w.Start -and $timeStr -lt $w.End) {
                $end = [TimeSpan]::Parse($w.End)
                $cur = [TimeSpan]::Parse($timeStr + ':00')
                $minutesToSwitch = [int]($end - $cur).TotalMinutes
                break
            }
        }
    } else {
        # 找今天下一个高峰窗口起点；找不到就是明天 09:00
        $candidates = @()
        foreach ($w in $script:DsPeakWindows) {
            if ($timeStr -lt $w.Start) { $candidates += [TimeSpan]::Parse($w.Start) }
        }
        $cur = [TimeSpan]::Parse($timeStr + ':00')
        if ($candidates.Count -gt 0) {
            $next = ($candidates | Sort-Object)[0]
            $minutesToSwitch = [int]($next - $cur).TotalMinutes
        } else {
            $minutesToSwitch = [int](([TimeSpan]::Parse('24:00') - $cur).TotalMinutes) + 9 * 60
        }
    }

    return [PSCustomObject]@{
        Phase            = if ($isPeak) { 'peak' } else { 'offpeak' }
        BejingTime       = $now.ToString('yyyy-MM-dd HH:mm:ss')
        DayOfWeek        = $now.DayOfWeek.ToString()
        IsWeekend        = $isWeekend
        IsHoliday        = $isHoliday
        MinutesToSwitch  = $minutesToSwitch
        # deepseek-flash 单价（元 / 百万 token）
        PriceInputHit    = if ($isPeak) { 0.04 } else { 0.02 }
        PriceInputMiss   = if ($isPeak) { 2.0 }  else { 1.0 }
        PriceOutput      = if ($isPeak) { 8.0 }  else { 4.0 }
    }
}

function Get-DsPricePhase { (Get-DsPhaseInfo).Phase }

function Test-DsOffPeak { (Get-DsPhaseInfo).Phase -eq 'offpeak' }

function Format-DsPhase {
    $i = Get-DsPhaseInfo
    $label = if ($i.Phase -eq 'offpeak') { '空闲时段（半价）' } else { '⚠ 高峰时段（全价）' }
    $sw = $i.MinutesToSwitch
    $swStr = if ($sw -ge 60) { "{0}小时{1}分" -f [int]($sw/60), ($sw%60) } else { "$sw 分钟" }
    "{0}  |  北京时间 {1} {2}  |  距切换 {3}" -f $label, $i.BejingTime, $i.DayOfWeek, $swStr
}

# 直接运行时打印当前状态
if ($MyInvocation.InvocationName -ne '.') {
    Format-DsPhase
}

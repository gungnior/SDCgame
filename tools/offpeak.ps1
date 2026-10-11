# offpeak.ps1 -- DeepSeek off-peak window detection
#
# Official rule (https://api-docs.deepseek.com/quick_start/pricing/):
#   Beijing time, Mon-Fri (excluding Chinese public holidays), 09:00-12:00 and
#   14:00-18:00 are PEAK hours. All other times -- including weekends and Chinese
#   public holidays in full -- are OFF-PEAK. Off-peak price is half of peak.
#
# Usage:
#   . .\tools\offpeak.ps1        # dot-source, then use the functions below
#   Get-DsPricePhase             # "offpeak" or "peak"
#   Get-DsPhaseInfo              # detailed object
#   .\tools\offpeak.ps1          # run directly to print current phase
#
# NOTE: This file is intentionally ASCII-only. Windows PowerShell 5.1 decodes
#       .ps1 files as the system ANSI codepage unless they carry a UTF-8 BOM,
#       which corrupts non-ASCII text. Keep scripts ASCII; keep Chinese in .md/.json.

Set-StrictMode -Version Latest

# Chinese public holidays (yyyy-MM-dd). Only list dates that fall on WEEKDAYS --
# weekends are already off-peak. Update after each State Council announcement.
# A missing file is treated as an empty list (worst case: a holiday weekday is
# misread as peak and you pay a few extra cents).
$script:DsHolidayFile = Join-Path $PSScriptRoot 'cn-holidays.json'

function Get-DsHolidays {
    if (Test-Path $script:DsHolidayFile) {
        try {
            $j = Get-Content $script:DsHolidayFile -Raw -Encoding UTF8 | ConvertFrom-Json
            return @($j.holidays)
        } catch {
            Write-Warning "cn-holidays.json parse failed, treating as no holidays: $($_.Exception.Message)"
            return @()
        }
    }
    return @()
}

# Interpreter-agnostic: PS7 -> pwsh.exe, PS5.1 -> powershell.exe
$script:PSExe = if ($PSVersionTable.PSEdition -eq 'Core') {
    Join-Path $PSHOME 'pwsh.exe'
} else {
    Join-Path $PSHOME 'powershell.exe'
}

# Peak windows: weekday 09:00-12:00 and 14:00-18:00
$script:DsPeakWindows = @(
    @{ Start = '09:00'; End = '12:00' },
    @{ Start = '14:00'; End = '18:00' }
)

function Get-DsPhaseInfo {
    <#
    .SYNOPSIS
      Returns DeepSeek price-phase info, evaluated in Beijing time regardless of
      the machine's local timezone.
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

    $cur = [TimeSpan]::Parse($timeStr + ':00')
    $minutesToSwitch = 0

    if ($isPeak) {
        foreach ($w in $script:DsPeakWindows) {
            if ($timeStr -ge $w.Start -and $timeStr -lt $w.End) {
                $minutesToSwitch = [int]([TimeSpan]::Parse($w.End) - $cur).TotalMinutes
                break
            }
        }
    } else {
        # Next peak-window start later today, else tomorrow 09:00
        $candidates = @()
        foreach ($w in $script:DsPeakWindows) {
            if ($timeStr -lt $w.Start) { $candidates += [TimeSpan]::Parse($w.Start) }
        }
        if ($candidates.Count -gt 0) {
            $next = ($candidates | Sort-Object)[0]
            $minutesToSwitch = [int]($next - $cur).TotalMinutes
        } else {
            # All of today's peak windows are past -> next is tomorrow 09:00
            $minutesToSwitch = [int]([TimeSpan]::FromHours(24) - $cur).TotalMinutes + 9 * 60
        }
    }

    return [PSCustomObject]@{
        Phase           = if ($isPeak) { 'peak' } else { 'offpeak' }
        BeijingTime     = $now.ToString('yyyy-MM-dd HH:mm:ss')
        DayOfWeek       = $now.DayOfWeek.ToString()
        IsWeekend       = $isWeekend
        IsHoliday       = $isHoliday
        MinutesToSwitch = $minutesToSwitch
        # deepseek-flash unit prices, CNY per million tokens
        PriceInputHit   = if ($isPeak) { 0.04 } else { 0.02 }
        PriceInputMiss  = if ($isPeak) { 2.0 }  else { 1.0 }
        PriceOutput     = if ($isPeak) { 8.0 }  else { 4.0 }
    }
}

function Get-DsPricePhase { (Get-DsPhaseInfo).Phase }

function Test-DsOffPeak { (Get-DsPhaseInfo).Phase -eq 'offpeak' }

function Format-DsPhase {
    $i = Get-DsPhaseInfo
    $label = if ($i.Phase -eq 'offpeak') { 'OFF-PEAK (half price)' } else { 'PEAK (full price)' }
    $sw = $i.MinutesToSwitch
    $swStr = if ($sw -ge 60) { '{0}h{1}m' -f [int]($sw / 60), ($sw % 60) } else { "$sw min" }
    '{0}  |  Beijing {1} {2}  |  switches in {3}' -f $label, $i.BeijingTime, $i.DayOfWeek, $swStr
}

if ($MyInvocation.InvocationName -ne '.') {
    Format-DsPhase
}

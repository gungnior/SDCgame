# verify.ps1 -- task acceptance checker
#
# Called by nightrun.ps1, or standalone:
#   .\tools\verify.ps1 -RuleJson '{"type":"file-exists","path":"a.txt"}'
#   .\tools\verify.ps1 -QueuePath .\tasks\queue.json -TaskId T-001
#
# Exit code: 0 = pass, 1 = fail. Failure reason goes to stdout.
#
# NOTE: ASCII-only on purpose. Windows PowerShell 5.1 decodes .ps1 as the system
#       ANSI codepage unless a UTF-8 BOM is present, which corrupts non-ASCII text
#       and breaks parsing. Scripts stay ASCII; Chinese lives in .md/.json.

param(
    [string]$RuleJson,
    [string]$QueuePath,
    [string]$TaskId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Interpreter-agnostic
$PSExe = if ($PSVersionTable.PSEdition -eq 'Core') { Join-Path $PSHOME 'pwsh.exe' } else { Join-Path $PSHOME 'powershell.exe' }

function Fail($msg) { Write-Output "FAIL: $msg"; exit 1 }
function Pass($msg) { Write-Output "PASS: $msg"; exit 0 }

# ---------- rule resolution ----------
if ($QueuePath -and $TaskId) {
    $q = Get-Content $QueuePath -Raw -Encoding UTF8 | ConvertFrom-Json
    $task = $q.tasks | Where-Object { $_.id -eq $TaskId }
    if (-not $task) { Fail "task $TaskId not found in queue" }
    $rule = $task.verify
} elseif ($RuleJson) {
    $rule = $RuleJson | ConvertFrom-Json
} else {
    Fail "need -RuleJson or (-QueuePath + -TaskId)"
}

$type = $rule.type
if (-not $type) { Fail "rule is missing 'type'" }

# All relative paths resolve against the workspace root (this script lives in <root>/tools/)
$root = Split-Path -Parent $PSScriptRoot
function Resolve-Target($p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $root $p)
}

switch ($type) {

    'file-exists' {
        $p = Resolve-Target $rule.path
        if (-not (Test-Path $p -PathType Leaf)) { Fail "file not found: $($rule.path)" }
        if ($rule.minBytes) {
            $sz = (Get-Item $p).Length
            if ($sz -lt $rule.minBytes) { Fail "file too small: $sz < $($rule.minBytes) bytes" }
        }
        Pass "$($rule.path) exists"
    }

    'command' {
        if (-not $rule.command) { Fail "command rule is missing 'command'" }
        Write-Output "run: $($rule.command)"
        $out = & $PSExe -NoProfile -ExecutionPolicy Bypass -Command $rule.command 2>&1
        $code = $LASTEXITCODE
        $out | Select-Object -First 40 | ForEach-Object { Write-Output "  $_" }
        if ($code -ne 0) { Fail "command exited with $code" }
        Pass "command ok"
    }

    'json-array' {
        $p = Resolve-Target $rule.path
        if (-not (Test-Path $p -PathType Leaf)) { Fail "file not found: $($rule.path)" }

        $raw = Get-Content $p -Raw -Encoding UTF8
        try { $data = $raw | ConvertFrom-Json } catch { Fail "JSON parse error: $($_.Exception.Message)" }
        if ($null -eq $data) { Fail "JSON is empty" }

        $arr = @($data)
        if ($rule.rootProperty) { $arr = @($data.$($rule.rootProperty)) }
        if ($arr.Count -eq 0) { Fail "array is empty" }

        if ($rule.minCount -and $arr.Count -lt $rule.minCount) {
            Fail "item count $($arr.Count) < required $($rule.minCount)"
        }
        if ($rule.maxCount -and $arr.Count -gt $rule.maxCount) {
            Fail "item count $($arr.Count) > allowed $($rule.maxCount)"
        }

        # required fields
        $missing = @()
        for ($i = 0; $i -lt $arr.Count; $i++) {
            foreach ($f in @($rule.requiredFields)) {
                if ($null -eq $arr[$i].$f -or "$($arr[$i].$f)" -eq '') {
                    $missing += "[$i] missing field '$f'"
                }
            }
        }
        if ($missing.Count -gt 0) {
            $missing | Select-Object -First 10 | ForEach-Object { Write-Output "  $_" }
            Fail "missing required fields: $($missing.Count)"
        }

        # unique key
        if ($rule.uniqueKey) {
            $uk = $rule.uniqueKey
            $keys = @($arr | ForEach-Object { "$($_.$uk)" })
            $dup = @($keys | Group-Object | Where-Object { $_.Count -gt 1 })
            if ($dup.Count -gt 0) {
                $dup | Select-Object -First 5 | ForEach-Object { Write-Output "  duplicate '$($_.Name)' x$($_.Count)" }
                Fail "$uk is not unique"
            }
        }

        # enum fields
        if ($rule.enumFields) {
            $uk = $rule.uniqueKey
            foreach ($prop in $rule.enumFields.PSObject.Properties) {
                $field = $prop.Name
                $allowed = @($prop.Value)
                $bad = @($arr | Where-Object { $allowed -notcontains "$($_.$field)" })
                if ($bad.Count -gt 0) {
                    $bad | Select-Object -First 5 | ForEach-Object {
                        Write-Output ("  {0}: {1}={2} not in allowed set" -f $_.$uk, $field, $_.$field)
                    }
                    Fail "field '$field' has illegal enum values"
                }
            }
        }

        Pass "$($rule.path): $($arr.Count) entries, fields and uniqueness ok"
    }

    'json-object' {
        $p = Resolve-Target $rule.path
        if (-not (Test-Path $p -PathType Leaf)) { Fail "file not found: $($rule.path)" }
        try { $data = (Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { Fail "JSON parse error: $($_.Exception.Message)" }
        foreach ($f in @($rule.requiredFields)) {
            if ($null -eq $data.$f) { Fail "missing field '$f'" }
        }
        Pass "$($rule.path) ok"
    }

    'no-network-permission' {
        # Red line: the project must not request the INTERNET permission (decision D-16)
        $hits = Get-ChildItem $root -Recurse -Include 'export_presets.cfg', 'AndroidManifest.xml' -ErrorAction SilentlyContinue |
            Select-String -Pattern 'INTERNET' -SimpleMatch
        if ($hits) {
            $hits | ForEach-Object { Write-Output "  $($_.Path):$($_.LineNumber) $($_.Line.Trim())" }
            Fail "INTERNET permission reference found (violates D-16)"
        }
        Pass "no INTERNET permission reference"
    }

    default { Fail "unknown rule type: $type" }
}

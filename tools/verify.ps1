# verify.ps1 —— 任务验收器
#
# 由 nightrun.ps1 调用，也可单独使用：
#   .\tools\verify.ps1 -RuleJson '{"type":"file-exists","path":"a.txt"}'
#   .\tools\verify.ps1 -QueuePath .\tasks\queue.json -TaskId T-001
#
# 退出码：0 = 通过，1 = 失败。失败原因走 stdout。

param(
    [string]$RuleJson,
    [string]$QueuePath,
    [string]$TaskId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Fail($msg) { Write-Output "FAIL: $msg"; exit 1 }
function Pass($msg) { Write-Output "PASS: $msg"; exit 0 }

# ---------- 规则解析 ----------
if ($QueuePath -and $TaskId) {
    $q = Get-Content $QueuePath -Raw | ConvertFrom-Json
    $task = $q.tasks | Where-Object { $_.id -eq $TaskId }
    if (-not $task) { Fail "队列中找不到任务 $TaskId" }
    $rule = $task.verify
} elseif ($RuleJson) {
    $rule = $RuleJson | ConvertFrom-Json
} else {
    Fail "需要 -RuleJson 或 (-QueuePath + -TaskId)"
}

$type = $rule.type
if (-not $type) { Fail "规则缺少 type 字段" }

# 所有路径相对工作区根目录（本脚本位于 <root>/tools/）
$root = Split-Path -Parent $PSScriptRoot
function Resolve-Target($p) {
    if ([System.IO.Path]::IsPathRooted($p)) { return $p }
    return (Join-Path $root $p)
}

switch ($type) {

    'file-exists' {
        $p = Resolve-Target $rule.path
        if (-not (Test-Path $p -PathType Leaf)) { Fail "文件不存在：$($rule.path)" }
        if ($rule.minBytes) {
            $sz = (Get-Item $p).Length
            if ($sz -lt $rule.minBytes) { Fail "文件过小：$sz < $($rule.minBytes) 字节" }
        }
        Pass "$($rule.path) 存在"
    }

    'command' {
        if (-not $rule.command) { Fail "command 规则缺少 command 字段" }
        Write-Output "运行：$($rule.command)"
        $out = & pwsh -NoProfile -Command $rule.command 2>&1
        $code = $LASTEXITCODE
        $out | Select-Object -First 40 | ForEach-Object { Write-Output "  $_" }
        if ($code -ne 0) { Fail "命令退出码 $code" }
        Pass "命令通过"
    }

    'json-array' {
        $p = Resolve-Target $rule.path
        if (-not (Test-Path $p -PathType Leaf)) { Fail "文件不存在：$($rule.path)" }

        $raw = Get-Content $p -Raw
        try { $data = $raw | ConvertFrom-Json } catch { Fail "JSON 解析失败：$($_.Exception.Message)" }
        if ($null -eq $data) { Fail "JSON 为空" }

        $arr = @($data)
        # 允许顶层是 {items:[...]} 形式
        if ($rule.rootProperty) {
            $arr = @($data.$($rule.rootProperty))
        }
        if ($arr.Count -eq 0) { Fail "数组为空" }

        if ($rule.minCount -and $arr.Count -lt $rule.minCount) {
            Fail "条目数 $($arr.Count) < 要求的 $($rule.minCount)"
        }
        if ($rule.maxCount -and $arr.Count -gt $rule.maxCount) {
            Fail "条目数 $($arr.Count) > 允许的 $($rule.maxCount)"
        }

        # 必需字段
        $missing = @()
        for ($i = 0; $i -lt $arr.Count; $i++) {
            foreach ($f in @($rule.requiredFields)) {
                if ($null -eq $arr[$i].$f -or "$($arr[$i].$f)" -eq '') {
                    $missing += "[$i] 缺字段 '$f'"
                }
            }
        }
        if ($missing.Count -gt 0) {
            $missing | Select-Object -First 10 | ForEach-Object { Write-Output "  $_" }
            Fail "缺失必需字段：$($missing.Count) 处"
        }

        # 唯一键
        if ($rule.uniqueKey) {
            $keys = $arr | ForEach-Object { "$($_."$($rule.uniqueKey)")" }
            $dup = $keys | Group-Object | Where-Object { $_.Count -gt 1 }
            if ($dup) {
                $dup | Select-Object -First 5 | ForEach-Object { Write-Output "  重复 '$($_.Name)' ×$($_.Count)" }
                Fail "$($rule.uniqueKey) 不唯一"
            }
        }

        # 枚举字段
        if ($rule.enumFields) {
            foreach ($prop in $rule.enumFields.PSObject.Properties) {
                $field = $prop.Name
                $allowed = @($prop.Value)
                $bad = $arr | Where-Object { $allowed -notcontains "$($_.$field)" }
                if ($bad) {
                    $bad | Select-Object -First 5 | ForEach-Object { Write-Output "  $($_.$rule.uniqueKey)：$field=$($_.$field) 不在允许值内" }
                    Fail "字段 '$field' 存在非法枚举值"
                }
            }
        }

        Pass "$($rule.path)：$($arr.Count) 条，字段与唯一性校验通过"
    }

    'json-object' {
        $p = Resolve-Target $rule.path
        if (-not (Test-Path $p -PathType Leaf)) { Fail "文件不存在：$($rule.path)" }
        try { $data = (Get-Content $p -Raw | ConvertFrom-Json) } catch { Fail "JSON 解析失败：$($_.Exception.Message)" }
        foreach ($f in @($rule.requiredFields)) {
            if ($null -eq $data.$f) { Fail "缺字段 '$f'" }
        }
        Pass "$($rule.path) 校验通过"
    }

    'no-network-permission' {
        # 红线检查：项目不得申请 INTERNET 权限（D-16）
        $hits = Get-ChildItem $root -Recurse -Include 'export_presets.cfg','AndroidManifest.xml' -ErrorAction SilentlyContinue |
                Select-String -Pattern 'INTERNET' -SimpleMatch
        if ($hits) {
            $hits | ForEach-Object { Write-Output "  $($_.Path):$($_.LineNumber) $($_.Line.Trim())" }
            Fail "发现 INTERNET 权限引用（违反 D-16）"
        }
        Pass "未发现 INTERNET 权限引用"
    }

    default { Fail "未知的规则类型：$type" }
}

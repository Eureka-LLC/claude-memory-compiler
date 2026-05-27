#Requires -Version 7
<#
.SYNOPSIS
    PreCompact hook — safety net before Claude Code auto-compacts the context window.
    Same architecture as session-end.ps1 but higher MIN_TURNS threshold.
#>

if ($env:CLAUDE_INVOKED_BY) { exit 0 }

$REPO_DIR  = Split-Path $PSScriptRoot -Parent
$brainFile = Join-Path $REPO_DIR "brain.path"
$BRAIN_DIR = if (Test-Path $brainFile) { (Get-Content $brainFile -Raw -Encoding UTF8).Trim() } else { $REPO_DIR }
$CLAUDE_DIR = Join-Path $BRAIN_DIR ".claude"
$FLUSH_LOG  = Join-Path $CLAUDE_DIR "flush.log"
$FLUSH_PS1 = Join-Path $REPO_DIR "scripts\flush.ps1"

$MAX_TURNS         = 30
$MAX_CONTEXT_CHARS = 15000
$MIN_TURNS         = 5

function Write-Log([string]$Level, [string]$Msg) {
    $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    "$ts $Level [pre-compact] $Msg" | Add-Content -Path $FLUSH_LOG -Encoding UTF8
}

try {
    $rawInput = [Console]::In.ReadToEnd()
    $rawInput = $rawInput -replace '(?<!\\)\\(?!["\\/bfnrtu])', '\\\\'
    $hookInput = $rawInput | ConvertFrom-Json
} catch {
    Write-Log "ERROR" "Failed to parse stdin: $_"
    exit 0
}

$sessionId     = $hookInput.session_id    ?? "unknown"
$transcriptStr = $hookInput.transcript_path ?? ""

Write-Log "INFO" "Fired: session=$sessionId"

if (-not $transcriptStr -or -not (Test-Path $transcriptStr)) {
    Write-Log "INFO" "SKIP: no transcript or missing: $transcriptStr"
    exit 0
}

$turns = [System.Collections.Generic.List[string]]::new()

foreach ($line in (Get-Content -Path $transcriptStr -Encoding UTF8)) {
    $line = $line.Trim()
    if (-not $line) { continue }
    try { $entry = $line | ConvertFrom-Json } catch { continue }

    $msg = $entry.message
    if ($msg -and $msg.PSObject.Properties['role']) { $role = $msg.role; $content = $msg.content }
    else { $role = $entry.role; $content = $entry.content }

    if ($role -notin @("user", "assistant")) { continue }

    if ($content -isnot [string]) {
        $parts = foreach ($block in @($content)) {
            if ($block.type -eq "text") { $block.text } elseif ($block -is [string]) { $block }
        }
        $content = $parts -join "`n"
    }

    $text = [string]$content
    if (-not $text.Trim()) { continue }
    $label = if ($role -eq "user") { "User" } else { "Assistant" }
    $turns.Add("**${label}:** $($text.Trim())`n")
}

if ($turns.Count -lt $MIN_TURNS) {
    Write-Log "INFO" "SKIP: only $($turns.Count) turns (min $MIN_TURNS)"
    exit 0
}

$recent  = if ($turns.Count -gt $MAX_TURNS) { $turns | Select-Object -Last $MAX_TURNS } else { $turns }
$context = $recent -join "`n"

if ($context.Length -gt $MAX_CONTEXT_CHARS) {
    $context  = $context.Substring($context.Length - $MAX_CONTEXT_CHARS)
    $boundary = $context.IndexOf("`n**")
    if ($boundary -gt 0) { $context = $context.Substring($boundary + 1) }
}

if (-not $context.Trim()) { Write-Log "INFO" "SKIP: empty context"; exit 0 }

$timestamp   = (Get-Date).ToString("yyyyMMdd-HHmmss")
$contextFile = Join-Path $BRAIN_DIR "flush-context-${sessionId}-${timestamp}.md"
[System.IO.File]::WriteAllText($contextFile, $context, [System.Text.Encoding]::UTF8)

try {
    Start-Process pwsh `
        -ArgumentList @("-NonInteractive", "-File", "`"$FLUSH_PS1`"", "`"$contextFile`"", "`"$sessionId`"") `
        -WindowStyle Hidden
    Write-Log "INFO" "Spawned flush.ps1 for session $sessionId ($($recent.Count) turns)"
} catch {
    Write-Log "ERROR" "Failed to spawn flush.ps1: $_"
}

#Requires -Version 7
<#
.SYNOPSIS
    SessionStart hook — injects knowledge base context into every new session.
    Reads from the configured brain directory. No API calls.
#>

$REPO_DIR      = Split-Path $PSScriptRoot -Parent
$brainFile     = Join-Path $REPO_DIR "brain.path"
$BRAIN_DIR     = if (Test-Path $brainFile) { (Get-Content $brainFile -Raw -Encoding UTF8).Trim() } else { $REPO_DIR }
$CLAUDE_DIR    = Join-Path $BRAIN_DIR ".claude"
$KNOWLEDGE_DIR = Join-Path $CLAUDE_DIR "knowledge"
$DAILY_DIR     = Join-Path $CLAUDE_DIR "daily"
$INDEX_FILE    = Join-Path $KNOWLEDGE_DIR "index.md"

$MAX_CONTEXT_CHARS = 20000
$MAX_LOG_LINES     = 30

function Get-RecentLog {
    for ($offset = 0; $offset -le 1; $offset++) {
        $date    = (Get-Date).AddDays(-$offset).ToString("yyyy-MM-dd")
        $logPath = Join-Path $DAILY_DIR "$date.md"
        if (Test-Path $logPath) {
            $lines  = Get-Content $logPath -Encoding UTF8
            $recent = if ($lines.Count -gt $MAX_LOG_LINES) { $lines | Select-Object -Last $MAX_LOG_LINES } else { $lines }
            return $recent -join "`n"
        }
    }
    return "(no recent daily log)"
}

$parts = [System.Collections.Generic.List[string]]::new()
$parts.Add("## Today`n$((Get-Date).ToString('dddd, MMMM dd, yyyy'))")

if (Test-Path $INDEX_FILE) {
    $parts.Add("## Knowledge Base Index`n`n$(Get-Content $INDEX_FILE -Raw -Encoding UTF8)")
} else {
    $parts.Add("## Knowledge Base Index`n`n(empty — no articles compiled yet)")
}

$parts.Add("## Recent Daily Log`n`n$(Get-RecentLog)")

$context = $parts -join "`n`n---`n`n"
if ($context.Length -gt $MAX_CONTEXT_CHARS) {
    $context = $context.Substring(0, $MAX_CONTEXT_CHARS) + "`n`n...(truncated)"
}

Write-Output (@{
    hookSpecificOutput = @{
        hookEventName     = "SessionStart"
        additionalContext = $context
    }
} | ConvertTo-Json -Depth 5 -Compress)

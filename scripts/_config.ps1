# Shared path constants — dot-source this file: . "$PSScriptRoot\_config.ps1"

# --- Repo paths (code, scripts, config) ---
$REPO_DIR    = Split-Path $PSScriptRoot -Parent
$SCRIPTS_DIR = $PSScriptRoot
$HOOKS_DIR   = Join-Path $REPO_DIR "hooks"
$AGENTS_FILE = Join-Path $REPO_DIR "AGENTS.md"

# --- Brain directory (personal data — configured once via setup.ps1) ---
$BRAIN_PATH_FILE = Join-Path $REPO_DIR "brain.path"
if (Test-Path $BRAIN_PATH_FILE) {
    $BRAIN_DIR = (Get-Content $BRAIN_PATH_FILE -Raw -Encoding UTF8).Trim()
} else {
    $BRAIN_DIR = $REPO_DIR
    Write-Warning "brain.path not configured. Run: pwsh -File setup.ps1"
}

# --- Claude data root (hidden subfolder, like .git/) ---
$CLAUDE_DIR      = Join-Path $BRAIN_DIR ".claude"

# --- Data paths (all inside .claude/) ---
$DAILY_DIR       = Join-Path $CLAUDE_DIR "daily"
$KNOWLEDGE_DIR   = Join-Path $CLAUDE_DIR "knowledge"
$CONCEPTS_DIR    = Join-Path $KNOWLEDGE_DIR "concepts"
$CONNECTIONS_DIR = Join-Path $KNOWLEDGE_DIR "connections"
$QA_DIR          = Join-Path $KNOWLEDGE_DIR "qa"
$REPORTS_DIR     = Join-Path $CLAUDE_DIR "reports"
$INDEX_FILE      = Join-Path $KNOWLEDGE_DIR "index.md"
$KB_LOG_FILE     = Join-Path $KNOWLEDGE_DIR "log.md"
$STATE_FILE      = Join-Path $CLAUDE_DIR "state.json"
$FLUSH_LOG       = Join-Path $CLAUDE_DIR "flush.log"

# --- Model / tuning ---
$DEFAULT_MODEL      = "claude-sonnet-4-6"
$COMPILE_AFTER_HOUR = 18
$MAX_TURNS          = 30
$MAX_CONTEXT_CHARS  = 15000

# --- Helpers ---
function Get-NowIso  { (Get-Date).ToString("yyyy-MM-ddTHH:mm:sszzz") }
function Get-TodayIso { (Get-Date).ToString("yyyy-MM-dd") }

function Get-FileHash256([string]$Path) {
    $sha   = [System.Security.Cryptography.SHA256]::Create()
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $hex   = ([BitConverter]::ToString($sha.ComputeHash($bytes)) -replace '-','').ToLower()
    $sha.Dispose()
    return $hex.Substring(0, 16)
}

function Load-State {
    if (Test-Path $STATE_FILE) {
        try { return (Get-Content $STATE_FILE -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable) }
        catch {}
    }
    return @{ ingested = @{}; query_count = 0; last_lint = $null; total_tokens = 0 }
}

function Save-State([hashtable]$State) {
    $State | ConvertTo-Json -Depth 10 | Set-Content -Path $STATE_FILE -Encoding UTF8
}

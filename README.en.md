# claude-memory-compiler (PowerShell)

**Your Claude Code conversations compile themselves into a structured knowledge base.**

When a session ends (or before auto-compaction), hooks capture the conversation transcript and extract what matters in the background: decisions, lessons, patterns, gotchas. Everything accumulates in daily logs, which are then compiled into structured cross-referenced articles.

> Inspired by: **[coleam00/claude-memory-compiler](https://github.com/coleam00/claude-memory-compiler)** — the original Python/uv implementation of the same idea.
> Knowledge architecture based on [Andrej Karpathy's LLM Knowledge Base](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

This repository is a **native PowerShell port** for Windows: no Python, no uv, no virtual environments. Just `pwsh` and the `claude` CLI from your existing subscription.

---

## Key concept: scripts and data live in separate folders

```
E:\tools\claude-memory-compiler\   ← repo (scripts, hooks) — clone here
    brain.path                      ← one line: path to your brain

E:\my-brain\                        ← knowledge base (data) — configured in setup.ps1
    .claude\                        ← all memory compiler data (like .git/)
        daily\                      ← all conversations land here automatically
        knowledge\
        │   concepts\
        │   connections\
        └── qa\
        reports\
```

`setup.ps1` asks where you want to store your data, saves the path to `brain.path`, and registers **global** Claude Code hooks. After that, **all your sessions from any project** feed into this one knowledge base.

To update scripts later: `git pull` — your brain data is untouched.

---

## Requirements

- Windows 10/11
- PowerShell 7+ (`pwsh`) — [download](https://github.com/PowerShell/PowerShell/releases)
- [Claude Code](https://claude.ai/download) — CLI or IDE extension (already installed if you're reading this)
- No separate API key needed — uses your subscription via the `claude` CLI

---

## Installation

```powershell
# 1. Clone into the folder that will become your knowledge base (any name works)
git clone https://github.com/YOUR_USERNAME/claude-memory-compiler-ps E:\my-brain
cd E:\my-brain

# 2. Run setup — creates directories, configures global hooks, checks environment
pwsh -File setup.ps1
```

> **Recommended: run `setup.ps1` from a terminal inside Claude Desktop** — this ensures hooks are registered in the same environment where the app runs and will start capturing sessions immediately. Open a terminal tab inside Claude Desktop and run `pwsh` from there.
>
> `setup.ps1` configures `ExecutionPolicy` automatically (see below).

---

## PowerShell Permissions (one time)

Windows blocks `.ps1` scripts by default. Run **once**, no admin rights needed:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

`setup.ps1` does this automatically. After that — no more permission dialogs.

Claude Code hooks also show no dialogs: once registered in `settings.json`, they run silently.

### Manual hook configuration

Hooks can be configured **globally** (active across all projects) in `~\.claude\settings.json`:

```json
{
  "hooks": {
    "SessionStart": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\session-start.ps1", "timeout": 15 }]
    }],
    "PreCompact": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\pre-compact.ps1", "timeout": 10 }]
    }],
    "SessionEnd": [{
      "matcher": "",
      "hooks": [{ "type": "command", "command": "pwsh -NonInteractive -File E:\\claude-memory-compiler\\hooks\\session-end.ps1", "timeout": 10 }]
    }]
  }
}
```

Replace `E:\\claude-memory-compiler` with the actual installation path (double backslashes required in JSON).

---

## Commands

```powershell
# Compile new daily logs into knowledge articles
pwsh -File scripts\compile.ps1

# Force recompile everything
pwsh -File scripts\compile.ps1 -All

# Compile a specific log file
pwsh -File scripts\compile.ps1 -Log .claude\daily\2026-05-26.md

# Query the knowledge base
pwsh -File scripts\query.ps1 "How do I usually handle API errors?"

# Query and save the answer back into the knowledge base
pwsh -File scripts\query.ps1 "What auth patterns do I use?" -FileBack

# Run knowledge base health checks (7 checks)
pwsh -File scripts\lint.ps1

# Structural checks only (no API calls, free)
pwsh -File scripts\lint.ps1 -StructuralOnly
```

### ⭐ Retroactive Compilation

Already using Claude Code before installing this tool? No problem — `retrocompile.ps1` scans all historical transcripts in `~/.claude/projects/` and compiles them into your knowledge base.

```powershell
# Dry run — see what would be processed
pwsh -File scripts\retrocompile.ps1 -DryRun

# Fast mode: script writes turns directly to daily logs → compile does 1 API call per day
# Runs in batch mode by default: progress report after every 5 sessions
pwsh -File scripts\retrocompile.ps1

# Batch of 10 sessions
pwsh -File scripts\retrocompile.ps1 -BatchSize 10

# No batching — process everything without intermediate reports
pwsh -File scripts\retrocompile.ps1 -NoBatch

# Quality mode: Claude summarizes each session individually → richer articles
pwsh -File scripts\retrocompile.ps1 -Mode Quality

# Process 20 sessions at a time (convenient for Quality mode)
pwsh -File scripts\retrocompile.ps1 -Mode Quality -Limit 20

# Specific projects only, from a given date
pwsh -File scripts\retrocompile.ps1 -Projects "my-saas","side-project" -Since 2026-01-01

# Fill daily logs only, skip compilation
pwsh -File scripts\retrocompile.ps1 -NoCompile

# Reprocess already-processed sessions
pwsh -File scripts\retrocompile.ps1 -Force
```

**Parameters:**

| Parameter | Description | Default |
|-----------|-------------|---------|
| `-Mode` | `Fast` or `Quality` | `Fast` |
| `-Projects` | Filter by project name (substring) | all |
| `-MinTurns` | Minimum turns per session | `3` |
| `-Since` | Only sessions from `YYYY-MM-DD` | all time |
| `-Limit` | Max **processed** sessions per run | unlimited |
| `-BatchSize` | Progress report after every N sessions | `5` |
| `-NoBatch` | Disable batch mode | — |
| `-DryRun` | Show plan without changes | — |
| `-Force` | Reprocess tracked sessions | — |
| `-NoCompile` | Fill daily logs only, skip compile | — |

> **How `-Limit` is counted:** the limit applies only to sessions that are actually processed — i.e. those that pass the `-MinTurns` threshold and get summarized or written. Already-processed sessions and sessions that are too short don't count toward the limit, but the script still has to scan past them.
>
> Example: your archive has 200 short test sessions (1–2 turns) and 10 meaningful ones. `-Limit 5` will make the script scroll through all 200 short sessions to find 5 good ones — and only then stop. This is expected behaviour: short sessions are marked as skipped in `retro-processed.json` along the way, so on the next run they are skipped instantly.

**Two modes explained:**

- **Fast** — the script writes conversation turns directly to daily logs (no API call), then `compile.ps1` extracts knowledge. ~1 API call per day. Ideal for processing your entire archive at once.
- **Quality** — Claude summarizes each session individually (like `flush.ps1`), then compile. ~1 API call per session. Better for selectively processing important projects.

The script remembers processed sessions in `retro-processed.json` — repeated runs are safe, already-processed sessions are skipped.

---

## How It Works

```
Conversation
  → SessionEnd / PreCompact hooks (file I/O only, no API)
  → scripts\flush.ps1 in background (Anthropic API: what's worth saving?)
  → daily\YYYY-MM-DD.md (daily log)
  → scripts\compile.ps1 (Anthropic API + tool use: write_file, append_file)
  → knowledge\concepts\, connections\, qa\ (knowledge base articles)
  → SessionStart hook injects index.md into next session
  → cycle repeats
```

### Components

| File | Purpose |
|------|---------|
| `hooks\session-end.ps1` | Captures transcript at session end |
| `hooks\pre-compact.ps1` | Safety net: captures context before auto-compaction |
| `hooks\session-start.ps1` | Injects knowledge base index into every session |
| `scripts\flush.ps1` | Background process: extracts knowledge from conversation |
| `scripts\compile.ps1` | Compiles daily logs into structured articles |
| `scripts\retrocompile.ps1` | **Retroactive compilation** of historical sessions into the knowledge base |
| `scripts\query.ps1` | Queries the knowledge base |
| `scripts\lint.ps1` | 7 knowledge base health checks |
| `scripts\_api.ps1` | Utilities: Anthropic API calls + tool-use loop |
| `scripts\_config.ps1` | Path constants |

### Why PowerShell instead of Python?

| | Python (`uv run`) | PowerShell |
|---|---|---|
| Startup time | 2–4 sec | ~0 sec |
| Hook timeout | 10 sec — risky | 10 sec — fine |
| Dependencies | uv, venv, packages | built-in |
| JSON | `json.loads()` | `ConvertFrom-Json` |
| HTTP | `httpx` / `requests` | `Invoke-RestMethod` |

---

## Project Structure

```
claude-memory-compiler/
├── hooks\
│   ├── session-end.ps1
│   ├── session-start.ps1
│   └── pre-compact.ps1
├── scripts\
│   ├── _config.ps1          # path constants (dot-sourced)
│   ├── _api.ps1             # Invoke-ClaudeCLI, Invoke-ParseFileOps
│   ├── flush.ps1            # background memory extraction
│   ├── compile.ps1          # daily log compiler
│   ├── retrocompile.ps1     # retroactive archive compilation
│   ├── query.ps1            # knowledge base queries
│   └── lint.ps1             # health checks
├── setup.ps1             # one-command setup
├── AGENTS.md             # knowledge base schema (read by LLM)
└── README.md
```

---

## API Cost Estimates

| Operation | Approximate cost |
|-----------|-----------------|
| Flush one session | ~$0.02–0.05 |
| Compile one daily log | ~$0.45–0.65 |
| Retrocompile Fast (full archive) | ~$0.45–0.65 × number of days |
| Retrocompile Quality (one session) | ~$0.02–0.05 |
| Query the knowledge base | ~$0.15–0.25 |
| Lint (structural only) | $0.00 |
| Lint (with contradiction check) | ~$0.15–0.25 |

Uses `claude-sonnet-4-6`. Model can be changed in `scripts\_config.ps1`.

---

## License

MIT

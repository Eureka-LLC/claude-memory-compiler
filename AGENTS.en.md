# AGENTS.md — Knowledge Base Schema

> Adapted from [Andrej Karpathy's LLM Knowledge Base](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) architecture.
> Original Python implementation: [coleam00/claude-memory-compiler](https://github.com/coleam00/claude-memory-compiler).
> Instead of ingesting external articles, this system compiles knowledge from your own AI conversations.

## The Compiler Analogy

```
daily/          = source code    (your conversations — the raw material)
LLM             = compiler       (extracts and organizes knowledge)
knowledge/      = executable     (structured, queryable knowledge base)
lint            = test suite     (health checks for consistency)
queries         = runtime        (using the knowledge)
```

---

## Architecture

### Layer 1: `daily/` — Conversation Logs (Immutable Source)

Daily logs capture what happened in your AI coding sessions. Append-only, never edited after the fact.

Each file follows this format:

```markdown
# Daily Log: YYYY-MM-DD

## Sessions

### Session (HH:MM)

_Project: folder-name — E:\Leskei\full\path_

**Context:** What the user was working on.

**Key Exchanges:**
- User asked about X, assistant explained Y
- Decided to use Z approach because...

**Decisions Made:**
- Chose library X over Y because...

**Lessons Learned:**
- Always do X before Y to avoid...

**Action Items:**
- [ ] Follow up on X
```

> **The `_Project:_` provenance line** is required under every session header. It records the **origin**
> of the lesson — which project it came from (the git repo root's folder name + full path). Within one
> daily log, sessions from different projects are marked per-session — the compiler uses this line to
> route lessons per project. If the project can't be determined, it is `unknown`.

### Layer 2: `knowledge/` — Compiled Knowledge (LLM-Owned)

```
knowledge/
├── index.md              # Master catalog — every article with one-line summary
├── log.md                # Append-only chronological build log
├── concepts/             # Atomic knowledge articles
├── connections/          # Cross-cutting insights linking 2+ concepts
└── qa/                   # Filed query answers
```

---

## Article Formats

### Concept Articles (`knowledge/concepts/`)

```markdown
---
title: "Concept Name"
aliases: [alternate-name]
tags: [domain, topic]
type: concept
scope: project
source_project: folder-name
domains: [domain1, domain2]
summary: "One-line description for the index"
sources:
  - "daily/2026-05-26.md"
created: 2026-05-26
updated: 2026-05-26
---

# Concept Name

[2-4 sentence core explanation]

## Key Points

- [Self-contained bullet points]

## Details

[Deeper explanation, encyclopedia-style]

## Related Concepts

- [[concepts/related-concept]] — How it connects

## Sources

- [[daily/2026-05-26.md]] — Initial discovery
```

#### New frontmatter fields (per-project routing)

| Field | Values | Purpose |
|-------|--------|---------|
| `type` | `concept` \| `rule` | `rule` — an imperative do/don't/gotcha lesson (a trap, an anti-pattern). `concept` — an encyclopedic article. Rules are the most valuable reusable lessons and are surfaced first. |
| `scope` | `global` \| `project` | `global` — the lesson is useful in **any** project. `project` — a fact specific to this project only. Drives the injection filter. |
| `source_project` | folder-name \| `unknown` | Provenance: the folder name of the git repo root the lesson came from (from the `_Project:_` line). With several sources — list them comma-separated. |
| `summary` | string | One-line description for the index. The index is a pure projection of frontmatter, so `summary` is required. |
| `domains` | list | Areas of applicability from the `domains.md` vocabulary (e.g. `[wordpress, css-frontend]`). The relevance axis for the domain filter. **Filled automatically** after compilation (`tag-domains.ps1`, picked strictly from the vocabulary) — the LLM compiler does not need to set this field. |

#### scope heuristic: where the line falls

The dividing axis is **portable mechanism vs local fact**, NOT the technology.

| Knowledge | scope | Why |
|-----------|-------|-----|
| SQLite, PowerShell, OS, or tool behaviour | `global` | works in any project |
| A specific DB schema, field names/types | `project` | a fact about one concrete system |
| A language or CLI bug/quirk | `global` | portable |
| Business logic, a specific system's API keys | `project` | one project's domain |

**The check question:** "will this lesson help in ANOTHER project?" Yes → `global`. Only inside this
code/domain → `project`.

**Bias toward global.** Error asymmetry: a false-`project` is worse than a false-`global` — a global
lesson (PowerShell, say) mislabelled as project-scoped sinks inside one project and won't back you up in
others. So tool / language / OS lessons default to `global`; send to `project` only explicit local facts
(schemas, fields, keys, business logic).

### Connection Articles (`knowledge/connections/`)

Created when a conversation reveals a non-obvious relationship between 2+ concepts.

```markdown
---
title: "Connection: X and Y"
type: concept
scope: global
connects:
  - "concepts/concept-x"
  - "concepts/concept-y"
sources:
  - "daily/2026-05-26.md"
created: 2026-05-26
updated: 2026-05-26
---

# Connection: X and Y

## The Connection

[What links these concepts]

## Key Insight

[The non-obvious relationship]

## Evidence

[Specific examples from conversations]

## Related Concepts

- [[concepts/concept-x]]
- [[concepts/concept-y]]
```

> Connections default to `scope: global` (a cross-project insight). If a connection links concepts from
> a single project only, `scope: project` + `source_project` is acceptable.

### Q&A Articles (`knowledge/qa/`)

```markdown
---
title: "Q: Original Question"
question: "The exact question asked"
consulted:
  - "concepts/article-1"
filed: 2026-05-26
---

# Q: Original Question

## Answer

[Synthesized answer with [[wikilinks]]]

## Sources Consulted

- [[concepts/article-1]] — Relevant because...
```

---

## Structural Files

### `knowledge/index.md`

The index is a **deterministic projection** of every article's frontmatter. It is built by `reindex.ps1`,
**not** the LLM. Columns:

```markdown
# Knowledge Base Index

| Article | Type | Scope | Project | Domains | Summary | Compiled From | Updated |
|---------|------|-------|---------|---------|---------|---------------|---------|
| [[concepts/example]] | rule | global | claude-memory-compiler | powershell | One-line description | daily/2026-05-26.md | 2026-05-26 |
```

The `session-start` hook parses this table and injects only rows where `Scope == global` OR
`Project == <current project>`. So the `Scope`/`Project` columns must be accurate — hence the
deterministic build.

### `knowledge/log.md`

```markdown
# Build Log

## [2026-05-26T18:00:00+03:00] compile | daily/2026-05-26.md
- Articles created: [[concepts/example]]
- Articles updated: (none)
```

---

## Compile Rules

When processing a daily log:

1. Read the daily log and current knowledge state. Each session has a `_Project:_` line — that is the
   **provenance** of that session's lessons.
2. For each piece of knowledge:
   - If an existing concept article covers it: **UPDATE** it, add the daily log as a source.
   - If it's a new topic: **CREATE** a new `concepts/` article.
3. If the log reveals a non-obvious connection: **CREATE** a `connections/` article.
4. **DON'T touch** `index.md` — it is rebuilt deterministically by `reindex.ps1`.
5. **APPEND** to `knowledge/log.md`.

**Mandatory on every concept:** `type`, `scope`, `source_project`, `summary` (see the heuristic above,
bias toward global), plus `title`, `sources`, `created`, `updated`. The `domains` field is filled
automatically after compilation by `tag-domains.ps1` (from the closed vocabulary) — the compiler doesn't
need to set it.

**Quality standards:**
- Complete YAML frontmatter on every article.
- Every article links to at least 2 others via `[[wikilinks]]`.
- Key Points: 3–5 self-contained bullet points.
- Details: 2+ paragraphs.
- Sources section cites the daily log.
- File names: lowercase, hyphens (e.g., `supabase-row-level-security.md`).

---

## Conventions

- **Wikilinks:** Obsidian-style `[[path/to/article]]` without `.md` extension.
- **Writing style:** Encyclopedia-style, factual, concise. Article content is in Russian; file names are in English.
- **Dates:** ISO 8601 (YYYY-MM-DD).
- **Frontmatter:** Every article must have `title`, `sources`, `created`, `updated`; concepts additionally `type`, `scope`, `source_project`, `summary`.

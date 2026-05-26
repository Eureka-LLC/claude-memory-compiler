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

### Connection Articles (`knowledge/connections/`)

Created when a conversation reveals a non-obvious relationship between 2+ concepts.

```markdown
---
title: "Connection: X and Y"
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

```markdown
# Knowledge Base Index

| Article | Summary | Compiled From | Updated |
|---------|---------|---------------|---------|
| [[concepts/example]] | One-line description | daily/2026-05-26.md | 2026-05-26 |
```

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

1. Read the daily log and current knowledge state.
2. For each piece of knowledge:
   - If an existing concept article covers it: **UPDATE** it, add the daily log as a source.
   - If it's a new topic: **CREATE** a new `concepts/` article.
3. If the log reveals a non-obvious connection: **CREATE** a `connections/` article.
4. **UPDATE** `knowledge/index.md` with new/modified entries.
5. **APPEND** to `knowledge/log.md`.

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
- **Writing style:** Encyclopedia-style, factual, concise.
- **Dates:** ISO 8601 (YYYY-MM-DD).
- **Frontmatter:** Every article must have `title`, `sources`, `created`, `updated`.

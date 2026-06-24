# preflight

`preflight` is a Claude Code plugin that automatically reviews **superpowers** spec and plan documents the moment you write them — a pre-flight check before any implementation takes off.

It detects newly written specs and plans, runs a deep adversarial review, applies every fixable finding in place (with a snapshot and a diff so nothing changes behind your back), surfaces genuine design decisions for you to make, and — for plans — delivers an explicit **Go / No-Go** verdict.

## Why

The `brainstorming → writing-plans → implementation` workflow produces a spec and then a plan, but the built-in self-checks are shallow. `preflight` adds a stronger gate on top: adversarial critique, completeness, spec↔plan consistency, and realism against the actual codebase — and it fixes what it finds instead of just listing it.

## How it works

Three decoupled building blocks:

| Block | Role |
|-------|------|
| **Hook** (`PostToolUse`) | Detects a written spec/plan file and *nudges* the review — advisory, never blocking. Debounced by content hash + an in-progress lock so it never loops on its own edits. |
| **Skill** (`reviewing-spec-and-plan`) | Orchestrates the review: a codebase fact-check, the review itself, fix application with snapshot+diff, and an adaptive re-review. |
| **Commands** | `/preflight-spec` and `/preflight-plan` for running a review manually. |

**Specs** are reviewed through an **Author ↔ Reviewer dialogue**: a senior reviewer raises substantive concerns round by round, the author defends or concedes with concrete replacements.

**Plans** are reviewed through a **6-stage chain** — five parallel reviewers (Completeness & Scope · Architecture & Convention Fit · Security · Edge Cases & Failure Modes · Sequencing & Effort) plus a consolidator that merges, de-duplicates, prioritises (Blocker vs. nice-to-have), applies fixes, and gives the Go/No-Go.

A dedicated fact-check classifies every code reference as *missing* (a real finding) versus *to-be-created* (a deliverable — never flagged), so greenfield plans aren't penalised for files that don't exist yet.

## Installation

```bash
# From the registry (once published)
/plugin install preflight

# From a local path
/plugin install /path/to/preflight/plugin
```

## Commands

| Command | What it does |
|---------|--------------|
| `/preflight-spec [path] [max-rounds]` | Review a spec via the Author/Reviewer dialogue. Defaults to the newest file in `docs/superpowers/specs/`. |
| `/preflight-plan [path] [max-rounds]` | Review a plan via the 6-stage chain against its spec. Defaults to the newest file in `docs/superpowers/plans/`. |

The hook triggers the same review automatically after a spec/plan is written.

## Specification

See [`docs/superpowers/specs/2026-06-24-preflight-design.md`](docs/superpowers/specs/2026-06-24-preflight-design.md) for the full design, and [`docs/superpowers/plans/2026-06-24-preflight.md`](docs/superpowers/plans/2026-06-24-preflight.md) for the implementation plan.

## License

MIT — see [LICENSE](LICENSE).

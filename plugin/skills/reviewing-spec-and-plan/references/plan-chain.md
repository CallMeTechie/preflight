# Plan Review: 6-Stage Chain

**Input (factlist):** The factlist is a table `reference | category | evidence`,
filtered to entries with category `missing` or `deviating`.

**design_forks:** findings whose resolution requires a real design decision with
no objectively correct answer.

Stages 1–5 each run as their own cheap-reviewer (in parallel). Each receives: PLAN,
the associated SPEC, and the factlist. Each delivers prioritised findings (Blocker/
Important/Optional) with concrete replacement text + source location and optional
`design_forks`.

1. **Completeness & Scope** — Are all spec requirements covered by a plan step?
   Hidden assumptions, open questions, scope creep, plan steps without a spec basis?
   What is missing entirely?
2. **Architecture & Convention Fit** — Read the project's CLAUDE.md + convention
   markers and check the plan against them (e.g. PHP: PSR-12/tabs, strict_types,
   PDO-only, security-first structure, soft deletes; Rust/TS analogously). Sensible
   patterns, no over-engineering, no reinvention of existing helpers.
3. **Security** — Input validation, AuthN/AuthZ paths, PII/secrets handling,
   SQLi/XSS surfaces, dependency risk. Multi-tenant + JWT: pay special attention.
4. **Edge Cases & Failure Modes** — Error paths, idempotency, race conditions,
   partial failures, rollback/retry behaviour. What happens on the second run?
5. **Sequencing & Effort** — Dependency order, what comes first, cutting into testable
   increments. Where are the biggest unknowns?

**Stage 6 — Consolidator (Orchestrator / main loop, not delegated):** merges all
findings, deduplicates, adversarially validates each finding (defend the existing
decision like the "Author" before applying it), prioritises (Blocker vs. Nice-to-have),
outputs the revised plan + explicit **Go/No-Go** with reasoning.

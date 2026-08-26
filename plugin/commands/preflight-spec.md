---
description: Run a preflight review (Author/Reviewer dialogue) on a superpowers spec, then apply all fixable findings with a snapshot+diff.
argument-hint: "[path] [max-rounds (default 5)]"
---

# Preflight: Spec

Invoke the skill `reviewing-spec-and-plan` in **Spec mode**.

Arguments: `$ARGUMENTS` = optional `[path] [max-rounds]`.
- Without `path`: pick the most recent file in `docs/superpowers/specs/` (by date in
  filename, then mtime).
- `max-rounds` default 5.

Execute the skill exactly following its step sequence (Lock → Snapshot → Security profile → Fact-check
→ Dialogue → Consolidation+Fixes+Diff → Adaptive re-review → Release lock/State/Report).

On a spec without a `<!-- preflight:security:begin -->` block the run starts with the
security profiler and asks about the project facts it cannot derive — new in 0.2.0.

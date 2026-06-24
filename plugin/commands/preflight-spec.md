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

Execute the skill exactly following its step sequence (Lock → Fact-check → Dialogue →
Snapshot+Fixes+Diff → Adaptive re-review → Release lock/State/Report).

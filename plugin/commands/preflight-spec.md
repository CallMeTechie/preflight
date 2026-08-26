---
description: Run a preflight review (Author/Reviewer dialogue) on a superpowers spec, then apply all fixable findings with a snapshot+diff.
argument-hint: "[path] [max-rounds (default 5)]"
---

# Preflight: Spec

Invoke the skill `reviewing-spec-and-plan` in **Spec mode**.

Arguments: `$ARGUMENTS` = optional `[path] [max-rounds]`.
- Without `path`: pick the most recent file in `docs/superpowers/specs/` that ends in
  `-design.md` — by date in the filename, then mtime. Backup files preflight writes itself
  (`*.preflight*.bak*`) are excluded by that suffix rule and must stay excluded: they carry the same
  date, sort **ahead** of the real spec, and this command **writes**. If the directory does not
  exist or holds no matching file, abort and ask for an explicit path — never fall back to any other
  file.
- `max-rounds` default 5.

Execute the skill exactly following its step sequence (Lock → Snapshot → Security profile → Fact-check
→ Dialogue → Consolidation+Fixes+Diff → Adaptive re-review → Release lock/State/Report).

On a spec without a `<!-- preflight:security:begin -->` block the run starts with the
security profiler and asks about the project facts it cannot derive — new in 0.2.0.

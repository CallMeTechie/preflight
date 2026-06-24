---
description: Run a preflight review (Author/Reviewer dialogue) on a superpowers spec, then apply all fixable findings with a snapshot+diff.
argument-hint: [path] [max-rounds (default 5)]
---

# Preflight: Spec

Invoke die Skill `reviewing-spec-and-plan` im **Spec-Modus**.

Argumente: `$ARGUMENTS` = optionaler `[path] [max-rounds]`.
- Ohne `path`: nimm die juengste Datei in `docs/superpowers/specs/` (nach Datum im
  Dateinamen, dann mtime).
- `max-rounds` default 5.

Fuehre die Skill genau nach ihrer Schrittfolge aus (Lock -> Faktencheck -> Dialog ->
Snapshot+Fixes+Diff -> adaptive Re-Review -> Lock loesen/State/Bericht).

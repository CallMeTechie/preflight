---
description: Run a preflight review (6-stage review chain) on a superpowers plan against its spec, apply all fixable findings with a snapshot+diff, and give a Go/No-Go.
argument-hint: [path] [max-rounds (default 5)]
---

# Preflight: Plan

Invoke die Skill `reviewing-spec-and-plan` im **Plan-Modus**.

Argumente: `$ARGUMENTS` = optionaler `[path] [max-rounds]`.
- Ohne `path`: nimm die juengste Datei in `docs/superpowers/plans/`.
- Loese die zugehoerige Spec auf: `Spec:`-Zeile bevorzugt, sonst Datum/Topic-
  Heuristik (bei Mehrdeutigkeit nachfragen).
- `max-rounds` default 5.

Fuehre die Skill genau nach ihrer Schrittfolge aus und gib am Ende das Go/No-Go aus.

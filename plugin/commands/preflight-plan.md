---
description: Run a preflight review (6-stage review chain) on a superpowers plan against its spec, apply all fixable findings with a snapshot+diff, and give a Go/No-Go.
argument-hint: "[path]"
---

# Preflight: Plan

Invoke the skill `reviewing-spec-and-plan` in **Plan mode**.

Arguments: `$ARGUMENTS` = optional `[path]`.
- Without `path`: pick the most recent file in `docs/superpowers/plans/`.
- Resolve the associated spec: prefer a `Spec:` line in the plan, otherwise use a
  date/topic heuristic (ask if ambiguous).

The plan chain has fixed stages (no rounds); the adaptive re-review is capped at
1 round maximum.

Execute the skill exactly following its step sequence and output the Go/No-Go at the end.

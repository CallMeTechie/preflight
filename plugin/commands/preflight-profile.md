---
description: Derive the security requirements for a spec from eleven project facts and write them into the spec as a marked block. Three modes — refresh, review, redo.
argument-hint: "[path] [--review|--redo]"
---

# Preflight: Security Profile

Invoke the skill `reviewing-spec-and-plan` in **Profile mode**.

Arguments: `$ARGUMENTS` = optional `[path]` plus an optional mode flag.
- Without `path`: pick the most recent file in `docs/superpowers/specs/` that ends in
  `-design.md` — by date in the filename, then mtime. Backup files preflight writes itself
  (`*.preflight*.bak*`) are excluded by that suffix rule and must stay excluded: they carry the same
  date, sort **ahead** of the real spec, and this command **writes**. If the directory does not
  exist or holds no matching file, abort and ask for an explicit path — never fall back to any other
  file.

Profile mode runs the skill's lock step, its security-profile step and its release step — no
fact-check, no review, no diff. The lock protocol including the refreshes at the profiler's human
gates belongs to the skill and to `references/security-profile.md`; it is not restated here. Both
existing commands follow the same shape, and a command that reimplements skill internals is a
second place to keep them correct.

## Modes

- **no flag** — read the stored facts, re-apply the rule matrix, update the
  table. Nothing is asked about the facts. For the case where the matrix
  changed. Existing `not-applicable` rows keep their status and reason. The
  updated table is shown and confirmed before it is written.
- **`--review`** — read the stored facts, apply the matrix, jump straight to
  Phase 4. Nothing is asked. The only action is setting rows to
  `not-applicable` with a mandatory dated reason, or taking that back. This is
  the regular way out of "this measure does not apply here" — `--redo` would
  demand eleven re-answered facts for a single row.
- **`--redo`** — discard the stored facts and run all five phases from the
  start. For scope changes.

In the two modes that read stored facts, a `preflight_security_facts_valid`
failure aborts and requires `--redo`. There is no Phase 2 to fall back to.

If the spec has no block at all, every mode behaves like `--redo`.

## Error paths

Release the lock on **every** exit, not only after Phase 5. A consistency violation in Phase 3, a
`preflight_security_facts_valid` failure, exit `2` or `3` from `preflight_security_block_state`, and
a user who declines at the Phase 4 gate all leave the lock behind otherwise — and preflight then
stays silent for up to 1800 s. If the run dies before cleanup, `clear-orphaned-lock.sh` removes the
lock at the next session start.

An abort before Phase 5 leaves the spec **unchanged**. Say so in the report, so the user knows there
is nothing to roll back.

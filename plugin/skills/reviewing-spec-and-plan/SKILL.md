---
name: reviewing-spec-and-plan
description: Use to run a deep preflight review of a superpowers spec or plan document — adversarial Author/Reviewer dialogue for specs, a 6-stage review chain for plans — then apply all fixable findings with a snapshot+diff. Invoked by the preflight PostToolUse hook (advisory) or the /preflight-spec and /preflight-plan commands.
---

# Reviewing Spec and Plan (preflight)

**Input:** `mode` (`spec` | `plan` | `profile`) + `path` to the file. Source: hook reminder
or command argument. Reference prompts are located under `references/` next to this file.

**Tiering (mandatory):** Delegate reviewer work to `preflight:reviewer`, codebase
fact-checking to `preflight:factchecker`, large mechanical fix-edits to
`preflight:editor`; the main loop handles only consolidation, judgment, and fix
decisions. Always address them prefixed — a bare `reviewer` or `editor` may
resolve to a user-defined agent with unknown tools.

**If an agent cannot be resolved**, do not abort. Fall back and say so:
`preflight:reviewer` and `preflight:factchecker` fall back to the built-in
`Explore` (which carries no `Write`, `Edit` or `NotebookEdit` — the read-only
guarantee survives), `preflight:editor` falls back to `general-purpose`. Name the
deviation verbatim in the final report: "Tiering inaktiv: `preflight:<name>` nicht
auflösbar, Lauf auf `<fallback>`." Never fall back to `general-purpose` for the
two read-only roles: it carries write tools, and the guarantee would fail
silently on the one path no test covers.

## Step 1 — Load context
- Read the file at `path`. If it is empty or has fewer than ~15 substantive lines:
  report "too little content for review" and abort.
- **Plan mode:** locate the associated spec. (1) If the plan contains a line
  `Spec: <path>`, use that. (2) Otherwise apply a heuristic: search both
  `docs/superpowers/specs/` **and** the plan file's own directory; match on
  filename (date/topic) **or** document heading/topic; ask the user if
  ambiguous. If no spec is found, proceed without the consistency dimension
  (state this explicitly).

## Step 2 — Set lock
Write the current Unix timestamp into `<project>/.claude/.preflight-running`
(`date +%s`). If creating the lock fails (exit != 0), **abort immediately and
report the error — never proceed without the lock.** Order is critical:
**lock first**, then edit, remove lock at the end, then write state (Step 9).
The lock suppresses review-own edits to the document in the hook.

The lock goes stale after 1800 s (`preflight_is_locked`). The profiler in Step 4
is the first part of the run that **waits on a human**, so refresh the timestamp
(`date +%s > <project>/.claude/.preflight-running`) after every answer in its
Phase 2, after the approval in its Phase 4, and immediately before its write in
Phase 5. A lock that expires mid-run lets the profiler's own write fire the
nudge and start a second review instance on the same file.

## Step 3 — Snapshot
Take the snapshot **before anything writes to the document** — the profiler in
Step 4 writes too, and a snapshot taken later would leave its change out of the
diff in Step 7.

If the file lives in a Git repository and is uncommitted, stage and commit only
the target file:
```
git add -- "<path>"
git commit -m "preflight: snapshot <basename> before review"
```
Before running the above, check whether unrelated changes are already staged: if
`git diff --cached --name-only` lists anything other than `<path>`, do NOT
commit — use the `.bak` method instead: `cp -- "<path>" "<path>.preflight.bak"`.
If the file is not in a Git repository, always use the `.bak` method.

The `.bak` path must not overwrite an existing snapshot: if
`<path>.preflight.bak` already exists, a previous run did not clean up. Pick the
first free `<path>.preflight<n>.bak` (n = 2, 3, …) and name the file you chose in
the report.

**Rollback.** From Step 4 on, the document may already carry the profiler's
write. Every abort after Step 3 therefore reports its rollback point explicitly:
`git checkout` of the snapshot commit, or `mv -f -- "<bak>" "<path>"`. An abort
that does not name its rollback point leaves the user unable to tell whether the
spec was touched.

## Step 4 — Security profile (spec mode and profile mode)
Source `plugin/lib/preflight-securitylib.sh` and call
`preflight_security_block_state "<path>"`.

- Exit `1` (no block): run the profiler from `references/security-profile.md`,
  all five phases. Security cannot be forgotten this way; a project without a
  network surface costs one question and ends with a block of a handful of rows.
- Exit `0` (block present): do **not** run the profiler. The dialogue's
  "Security-Profil" topic checks the block for drift instead.
- Exit `2` (damaged markers): abort the run, report the marker state, write
  nothing.
- Exit `3` (path unreadable): abort the run and report the path — the spec was not
  found. Do **not** report a marker problem; that sends the user hunting for a
  corruption that is not there.

In **profile mode** this step *is* the run: after it, jump straight to Step 9. The
flag from `/preflight-profile` (`--review` / `--redo`) selects the profiler's entry
point. In **plan mode** the step does not apply — the profiler only ever touches
specs.

## Step 5 — Fact-check
Dispatch a `preflight:factchecker` with the prompt from `references/factcheck.md` plus
the document content. Only carry findings of type `missing` /
`deviating` into the review.

## Step 6 — Review
- **Spec mode:** Dispatch ONE `preflight:reviewer` with `references/spec-dialogue.md`
  (document + fact list + max-rounds).
- **Plan mode:** The main loop builds FIVE SEPARATE dispatches to `preflight:reviewer`
  and runs them in PARALLEL. Each dispatch assigns EXACTLY ONE stage explicitly —
  for example: "You are Reviewer N. Your mandate is exclusively Stage N: <title>
  from references/plan-chain.md". Do NOT pass the full plan-chain.md text
  verbatim to all five; instead quote only the relevant stage mandate per dispatch.
  Each reviewer receives: plan + spec + fact list + its single stage mandate.
  Stage 6 (Consolidator) is NOT delegated — it is Step 7 of this skill.

## Step 7 — Consolidation, Fixes, Diff (main loop) (= Stage 6 of the plan chain: Consolidator)
1. Merge and deduplicate findings; validate each finding adversarially before
   applying it (no weak objection is adopted blindly).

   **Exception, plan mode:** findings that follow purely from a `SEC-COVERAGE`
   classification in Stage 3 plus the security rule in `references/plan-chain.md`
   are **not** re-validated adversarially — they are taken as they are. What is
   arguable is the classification, and that argument belongs in Stage 3. Without
   this exception the adversarial pass eats the determinism the rule promises.
2. Apply ALL fixable findings directly to the document (large mechanical edits via
   `preflight:editor`). Do NOT guess on genuine `design_forks` — collect them for Step 9.

   **Except the security block.** Findings from the "Security-Profil" topic are
   never `fixable`; report them with the single recommendation
   `/preflight-profile --redo`. The region between
   `<!-- preflight:security:begin -->` and `<!-- preflight:security:end -->` is
   write-protected for every step outside the profiler — typos in its prose column
   included. Never dispatch `preflight:editor` at that region, and repeat the
   prohibition verbatim in **every** dispatch to it: the block's protection against
   the editor is prompt-borne, not structural, so it holds only where it is stated.

   **Verify it, do not trust it.** `preflight:editor` carries `Write`. Record the
   block right after Step 4:

       sed -n '/<!-- preflight:security:begin -->/,/<!-- preflight:security:end -->/p' \
           < "<path>" > "<project>/.claude/.preflight-secblock"

   and compare after the last fix, before the diff:

       sed -n '/<!-- preflight:security:begin -->/,/<!-- preflight:security:end -->/p' \
           < "<path>" | diff -q - "<project>/.claude/.preflight-secblock"

   A difference means the protection was breached: restore the region from the
   snapshot, drop the fix that caused it, and report it as a Blocker. Delete the
   recording when the lock is released.
3. Show the user the **diff** against the snapshot (not just a fix list).
4. **Plan mode:** formulate an explicit **Go/No-Go** with reasoning.

## Step 8 — Adaptive re-review
Weigh whether a second pass is warranted and state the decision with a one-sentence
reason:
- **Focused round** (only changed sections/dimensions) for local fixes.
- **Full round** (dialogue or full chain) for structural or broad changes.
- **No second pass** for trivial corrections only.

**Hard cap:** at most ONE re-review round. After the second pass through Steps 6–7
the answer is always "no further round", regardless of how broad the changes were.

If a re-review round starts, **refresh the lock timestamp first**:
`date +%s > <project>/.claude/.preflight-running`. This prevents the 1800 s staleness
threshold from expiring in the middle of a long re-review.

During re-review the lock remains active and Steps 6–7 apply again.

## Step 9 — Release lock, write state, report
- Remove `.preflight-running`, **then** write the reviewed state.
- Before writing: verify that `path` contains no control characters by calling
  `preflight_path_ok "<path>"`. If it returns non-zero, abort without writing the
  state (a corrupt state line would break the hook).
- Write the state using the shell function from `plugin/hooks/preflight-hooklib.sh`:
  ```
  preflight_record_reviewed "<state_file>" "<path>" "<hash>"
  ```
  (`<state_file>` = `<project>/.claude/.preflight-reviewed`). This atomically
  replaces the existing line for the same path and prevents unbounded growth.
  Always pass the **absolute** path from the nudge (`path=…`), never a relative
  path. `preflight_record_reviewed` canonicalizes the path internally, so
  equivalent forms (e.g. `/a/./b.md` vs `/a/b.md`) are correctly debounced.
- Present open `design_forks` to the user as a short decision list (one question
  per fork).
- Report compactly: summary table, diff reference, open forks, re-review decision,
  and (plan mode) the Go/No-Go.

## Error paths
- If you abort early, remove the lock anyway (otherwise the hook stays silent until
  the 30-minute staleness expires). If the run is interrupted before you can clean up
  (a lost tool result, a hard abort), the `clear-orphaned-lock.sh` SessionStart hook
  removes the leftover lock on the next session, so preflight re-arms automatically.
- If `.claude/` does not exist, create it.

---
name: reviewing-spec-and-plan
description: Use to run a deep preflight review of a superpowers spec or plan document — adversarial Author/Reviewer dialogue for specs, a 6-stage review chain for plans — then apply all fixable findings with a snapshot+diff. Invoked by the preflight PostToolUse hook (advisory) or the /preflight-spec and /preflight-plan commands.
---

# Reviewing Spec and Plan (preflight)

**Input:** `mode` (`spec` | `plan`) + `path` to the file. Source: hook reminder
or command argument. Reference prompts are located under `references/` next to this file.

**Tiering (mandatory):** Delegate reviewer work to `cheap-reviewer`, codebase
fact-checking to `cheap-explorer`, large mechanical fix-edits to `cheap-coder`;
the main loop handles only consolidation, judgment, and fix decisions.

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
**lock first**, then edit, remove lock at the end, then write state (Step 7).
The lock suppresses review-own edits to the document in the hook.

## Step 3 — Fact-check
Dispatch a `cheap-explorer` with the prompt from `references/factcheck.md` plus
the document content. Only carry findings of type `missing` /
`deviating` into the review.

## Step 4 — Review
- **Spec mode:** Dispatch ONE `cheap-reviewer` with `references/spec-dialogue.md`
  (document + fact list + max-rounds).
- **Plan mode:** The main loop builds FIVE SEPARATE dispatches to `cheap-reviewer`
  and runs them in PARALLEL. Each dispatch assigns EXACTLY ONE stage explicitly —
  for example: "You are Reviewer N. Your mandate is exclusively Stage N: <title>
  from references/plan-chain.md". Do NOT pass the full plan-chain.md text
  verbatim to all five; instead quote only the relevant stage mandate per dispatch.
  Each reviewer receives: plan + spec + fact list + its single stage mandate.
  Stage 6 (Consolidator) is NOT delegated — it is Step 5 of this skill.

## Step 5 — Consolidation, Snapshot, Fixes, Diff (main loop) (= Stage 6 of the plan chain: Consolidator)
1. Merge and deduplicate findings; validate each finding adversarially before
   applying it (no weak objection is adopted blindly).
2. **Snapshot before the first fix:** if the file lives in a Git repository and is
   uncommitted, stage and commit only the target file:
   ```
   git add -- "<path>"
   git commit -m "preflight: snapshot <basename> before review"
   ```
   Before running the above, check whether unrelated changes are already staged:
   if `git diff --cached --name-only` lists anything other than `<path>`, do NOT
   commit — use the `.bak` method instead: `cp -- "<path>" "<path>.preflight.bak"`.
   If the file is not in a Git repository, always use the `.bak` method.
3. Apply ALL fixable findings directly to the document (large mechanical edits via
   `cheap-coder`). Do NOT guess on genuine `design_forks` — collect them for Step 7.
4. Show the user the **diff** against the snapshot (not just a fix list).
5. **Plan mode:** formulate an explicit **Go/No-Go** with reasoning.

## Step 6 — Adaptive re-review
Weigh whether a second pass is warranted and state the decision with a one-sentence
reason:
- **Focused round** (only changed sections/dimensions) for local fixes.
- **Full round** (dialogue or full chain) for structural or broad changes.
- **No second pass** for trivial corrections only.

**Hard cap:** at most ONE re-review round. After the second pass through Steps 4–5
the answer is always "no further round", regardless of how broad the changes were.

If a re-review round starts, **refresh the lock timestamp first**:
`date +%s > <project>/.claude/.preflight-running`. This prevents the 1800 s staleness
threshold from expiring in the middle of a long re-review.

During re-review the lock remains active and Steps 4–5 apply again.

## Step 7 — Release lock, write state, report
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
  the 30-minute staleness expires).
- If `.claude/` does not exist, create it.

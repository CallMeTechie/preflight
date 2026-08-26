# preflight Plugin

Advisory nudge + review skill for superpowers spec and plan documents.

## Components

### 1a. Hook — `plugin/hooks/detect-spec-plan-write.sh`

PostToolUse hook. Fired after every `Write` and `Edit` call.
- Detects spec files (`docs/superpowers/specs/*-design.md`) and plan files
  (`docs/superpowers/plans/*.md`) by path.
- **Never blocks.** On a match it emits `hookSpecificOutput.additionalContext` —
  a text nudge asking Claude to invoke the skill.
- Suppresses the nudge when: (a) the file has already been reviewed under its current
  hash (state file), or (b) a review is already running (lock file).

### 1b. Hook — `plugin/hooks/clear-orphaned-lock.sh`

SessionStart hook. Removes a leftover `.preflight-running` lock at the start of a
session. The lock is set and released by the main loop inside the skill; if a run is
interrupted (user abort, a lost/errored tool result, a crash) the release never runs
and the lock silently suppresses the nudge until it goes stale (default 30 min). A
review can never span a session boundary, so any lock present at SessionStart is
orphaned and safe to remove — this makes the review **abort-safe**: preflight re-arms
itself on the next session with no manual cleanup. **Manual clear** (same session):
`rm -f <project>/.claude/.preflight-running`.

### 2. Skill — `plugin/skills/reviewing-spec-and-plan/`

Core logic. Triggered by the hook nudge **or** directly by a command.

**Spec mode:** adversarial Author/Reviewer dialogue (up to `max-rounds`).
**Plan mode:** 6-stage review chain (Stages 1–5 in parallel, Stage 6 = Consolidator).

Flow: Set lock → Snapshot → Security profile → Fact-check (`preflight:factchecker`)
→ Review (`preflight:reviewer`) → Consolidate + Fixes + Diff → Adaptive re-review
→ Release lock → Write state → Report + open design forks.

### 3. Commands — `plugin/commands/`

| Command              | Description                                          |
|----------------------|------------------------------------------------------|
| `/preflight-spec`    | Starts the skill in Spec mode for `[path]`           |
| `/preflight-plan`    | Starts the skill in Plan mode for `[path]`           |
| `/preflight-profile` | Security profile for `[path]`; `--review` / `--redo`  |

Without a `path` argument the most recent matching file in the respective directory
is used. `/preflight-spec` accepts an optional second parameter `max-rounds` (default 5).

### 4. Agents — `plugin/agents/`

| Agent | Role | Tools | Model |
|-------|------|-------|-------|
| `preflight:factchecker` | Step 5, references against the codebase | read-only | `sonnet` |
| `preflight:reviewer` | Step 6, dialogue and the five plan stages | read-only | `inherit` |
| `preflight:editor` | Step 7, large mechanical fix-edits | read/write | `sonnet` |

`factchecker` and `reviewer` carry no `Write` or `Edit`, and
`tests/test_agents_wellformed.sh` holds that: exactly one file under
`plugin/agents/` may carry write tools, and it must be `editor.md`.

### 5. Security profiler

`/preflight-profile` and step 4 of the skill. Derives eleven project facts, applies
`references/security-matrix.md`, and writes a marked block into the spec. See
`references/security-profile.md`. The shell side lives in
`plugin/lib/preflight-securitylib.sh` — deliberately not in `plugin/hooks/`, which the
PostToolUse hook sources on every `Write` and `Edit` and which stays free of domain
knowledge.

## State Files

Both located under `<project-root>/.claude/`:

| File                       | Meaning                                                      |
|----------------------------|--------------------------------------------------------------|
| `.preflight-running`       | Unix timestamp; set while a review is running (lock).        |
|                            | Stale after 1800 s (30 min) — hook ignores it then. Also     |
|                            | cleared at SessionStart, so an interrupted run never leaves   |
|                            | it stuck (see hook 1b).                                       |
| `.preflight-reviewed`      | One line `<sha256>\t<path>` per reviewed file.               |
|                            | A new hash for the same file → hook nudges again.            |

## Advisory Nature

The hook **cannot** force the skill invocation — it only sends a hint via
`additionalContext`. Claude decides whether it makes sense to follow the nudge
(usually yes, unless the file is obviously a work-in-progress).

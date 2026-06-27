# preflight Plugin

Advisory nudge + review skill for superpowers spec and plan documents.

## Components

### 1a. Hook — `plugin/hooks/detect-spec-plan-write.sh`

PostToolUse hook. Fired after every `Write` call.
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

Flow: Set lock → Fact-check (`cheap-explorer`) → Review (`cheap-reviewer`)
→ Consolidate findings → Snapshot + Fixes + Diff → Adaptive re-review →
Release lock → Write state → Report + open design forks.

### 3. Commands — `plugin/commands/`

| Command              | Description                                          |
|----------------------|------------------------------------------------------|
| `/preflight-spec`    | Starts the skill in Spec mode for `[path]`           |
| `/preflight-plan`    | Starts the skill in Plan mode for `[path]`           |

Without a `path` argument the most recent matching file in the respective directory
is used. `/preflight-spec` accepts an optional second parameter `max-rounds` (default 5).

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

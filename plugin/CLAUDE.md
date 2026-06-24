# preflight Plugin

Advisory nudge + review skill for superpowers spec and plan documents.

## Three Components

### 1. Hook — `plugin/hooks/detect-spec-plan-write.sh`

PostToolUse hook. Fired after every `Write` call.
- Detects spec files (`docs/superpowers/specs/*-design.md`) and plan files
  (`docs/superpowers/plans/*.md`) by path.
- **Never blocks.** On a match it emits `hookSpecificOutput.additionalContext` —
  a text nudge asking Claude to invoke the skill.
- Suppresses the nudge when: (a) the file has already been reviewed under its current
  hash (state file), or (b) a review is already running (lock file).

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
|                            | Stale after 1800 s (30 min) — hook ignores it then.         |
| `.preflight-reviewed`      | One line `<sha256>\t<path>` per reviewed file.               |
|                            | A new hash for the same file → hook nudges again.            |

## Advisory Nature

The hook **cannot** force the skill invocation — it only sends a hint via
`additionalContext`. Claude decides whether it makes sense to follow the nudge
(usually yes, unless the file is obviously a work-in-progress).

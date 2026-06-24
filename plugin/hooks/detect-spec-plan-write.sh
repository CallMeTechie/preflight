#!/usr/bin/env bash
# PostToolUse hook: nudge the preflight review skill when a spec/plan doc is written.
# Never blocks. Emits hookSpecificOutput.additionalContext on stdout when a nudge is due.
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/preflight-hooklib.sh"

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$FILE" ] || exit 0

MODE="$(preflight_detect_mode "$FILE")"
[ -n "$MODE" ] || exit 0

ROOT="$(preflight_find_root "$FILE" "$CWD")"
LOCK="$ROOT/.claude/.preflight-running"
STATE="$ROOT/.claude/.preflight-reviewed"

preflight_is_locked "$LOCK" && exit 0

HASH="$(preflight_hash "$FILE")"
preflight_already_reviewed "$STATE" "$FILE" "$HASH" && exit 0

CONTEXT="Eine ${MODE}-Datei wurde nach ${FILE} geschrieben. Bevor du fortfaehrst, invoke die Skill reviewing-spec-and-plan (Plugin preflight) mit Modus=${MODE} und Pfad=${FILE}."

jq -n --arg ctx "$CONTEXT" \
	'{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0

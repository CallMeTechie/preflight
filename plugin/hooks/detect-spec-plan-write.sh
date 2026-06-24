#!/usr/bin/env bash
# PostToolUse hook: nudge the preflight review skill when a spec/plan doc is written.
# Never blocks. Emits hookSpecificOutput on stdout when a nudge is due.
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/preflight-hooklib.sh"

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$FILE" ] || exit 0
preflight_path_ok "$FILE" || exit 0
FILE="$(preflight_canon_path "$FILE")"

MODE="$(preflight_detect_mode "$FILE")"
[ -n "$MODE" ] || exit 0

ROOT="$(preflight_find_root "$FILE" "$CWD")"
LOCK="$ROOT/.claude/.preflight-running"
STATE="$ROOT/.claude/.preflight-reviewed"

preflight_is_locked "$LOCK" && exit 0

HASH="$(preflight_hash "$FILE")"
preflight_already_reviewed "$STATE" "$FILE" "$HASH" && exit 0

CONTEXT="A ${MODE} document was written to ${FILE}. Before continuing, invoke the reviewing-spec-and-plan skill (preflight plugin) with mode=${MODE} and path=${FILE}."

jq -n --arg ctx "$CONTEXT" --arg mode "$MODE" --arg file "$FILE" \
	'{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx,preflightMode:$mode,preflightPath:$file}}'
exit 0

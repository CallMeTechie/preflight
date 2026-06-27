#!/usr/bin/env bash
# SessionStart hook: clear an orphaned preflight review lock.
#
# Rationale: the review lock (.preflight-running) is set by the main loop in the
# reviewing-spec-and-plan skill and removed again at the end (Step 7). If a run is
# interrupted (user abort, a lost/errored tool result, a crash) the cleanup never
# happens and the lock stays behind, silencing the PostToolUse nudge until the
# staleness threshold expires (default 30 min). A review can never span a session
# boundary, so a lock present at SessionStart is almost always orphaned. The one
# exception is a *concurrent* session that just started a review milliseconds ago:
# to avoid clobbering it, we leave a lock that is still "fresh" (< FRESH_WINDOW s)
# and only remove older ones (an orphaned lock is essentially always far older by
# the time a new session opens). Emits nothing on stdout.

FRESH_WINDOW=90
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/preflight-hooklib.sh"

INPUT="$(cat)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$CWD" ] || CWD="$PWD"

# Resolve the same project root the PostToolUse hook would compute, walking up
# from the session's working directory.
ROOT="$(preflight_find_root "$CWD/_" "$CWD")"
LOCK="$ROOT/.claude/.preflight-running"

if [ -f "$LOCK" ] && ! preflight_is_locked "$LOCK" "$FRESH_WINDOW"; then
	# Lock is older than FRESH_WINDOW (or unreadable/garbage) -> orphaned -> remove.
	rm -f -- "$LOCK" 2>/dev/null \
		&& printf 'preflight: cleared orphaned review lock %s\n' "$LOCK" >&2
fi
exit 0

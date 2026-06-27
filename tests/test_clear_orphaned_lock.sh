#!/usr/bin/env bash
# Tests for the SessionStart hook that clears an orphaned review lock.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../plugin/hooks/clear-orphaned-lock.sh"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

run_hook() { printf '{"cwd":"%s"}' "$1" | bash "$HOOK"; }
old_ts() { echo $(( $(date +%s) - 300 )); }   # 5 min old: well past FRESH_WINDOW (90 s)

# Project root is discovered by walking up from cwd to a dir with .git/.claude.
tmp="$(mktemp -d)"
mkdir -p "$tmp/proj/.claude/sub"
LOCK="$tmp/proj/.claude/.preflight-running"

# (1) Orphaned (old) lock at the project root is removed, even when cwd is a subdir.
old_ts > "$LOCK"
run_hook "$tmp/proj/.claude/sub" >/dev/null 2>&1
[ ! -f "$LOCK" ] && ok "old lock cleared from subdir cwd" || bad "old lock not cleared"

# (2) No lock present -> hook is a no-op and exits cleanly.
run_hook "$tmp/proj" >/dev/null 2>&1
[ "$?" -eq 0 ] && ok "no lock -> exit 0" || bad "no lock -> non-zero exit"

# (3) Old lock clear is reported on stderr (visible in debug).
old_ts > "$LOCK"
err="$(run_hook "$tmp/proj" 2>&1 >/dev/null)"
printf '%s' "$err" | grep -q "cleared orphaned review lock" && ok "clear is reported on stderr" || bad "no stderr report on clear"

# (4) A FRESH lock (< 90 s, e.g. a concurrent session's just-started review) is preserved.
date +%s > "$LOCK"
run_hook "$tmp/proj" >/dev/null 2>&1
[ -f "$LOCK" ] && ok "fresh lock preserved (no concurrent-session clobber)" || bad "fresh lock was clobbered"

# (5) A garbage / unreadable lock is treated as orphaned and removed.
printf 'not-a-timestamp' > "$LOCK"
run_hook "$tmp/proj" >/dev/null 2>&1
[ ! -f "$LOCK" ] && ok "garbage lock removed" || bad "garbage lock not removed"

# (6) The state file (.preflight-reviewed) must NOT be touched.
printf 'abc\t%s\n' "$tmp/proj/doc.md" > "$tmp/proj/.claude/.preflight-reviewed"
old_ts > "$LOCK"
run_hook "$tmp/proj" >/dev/null 2>&1
[ -f "$tmp/proj/.claude/.preflight-reviewed" ] && ok "reviewed-state file left intact" || bad "reviewed-state file was removed"

# (7) Missing cwd in payload -> $PWD fallback; no .claude under a bare tmp dir -> no-op, exit 0.
bare="$(mktemp -d)"
( cd "$bare" && printf '{}' | bash "$HOOK" >/dev/null 2>&1 )
[ "$?" -eq 0 ] && ok "missing cwd -> PWD fallback, clean exit" || bad "missing cwd -> non-zero exit"
rm -rf "$bare"

rm -rf "$tmp"
exit $fail

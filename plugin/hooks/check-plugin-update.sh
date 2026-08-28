#!/usr/bin/env bash
# SessionStart hook: notify when a newer preflight version is available.
#
# Rationale: Claude Code has no built-in update notification for plugins — a
# user who never runs `claude plugin update` by hand stays on an old version
# forever. This hook closes that gap for preflight itself: once a day, at
# most, it compares the installed version (this repo's own plugin.json)
# against the version published in the marketplace manifest of the repo
# named in plugin.json's `repository` field (so a fork checks its own repo,
# not upstream). A newer version prints a short nudge to stderr; anything
# else is silent. Never blocks, never touches stdout, always exits 0.
#
# Test seam: if PREFLIGHT_UPDATE_MANIFEST is set, its content is read from
# that file instead of fetched over the network — this is how the test suite
# exercises the comparison logic without reaching the network.
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/preflight-hooklib.sh"

# SessionStart payload arrives on stdin; nothing in it is needed here, but it
# must still be drained.
cat >/dev/null

# No HOME -> nowhere to read/write state; bail before any $HOME reference
# trips `set -u`.
[ -n "${HOME:-}" ] || exit 0

# 1. Explicit opt-out via environment.
[ -n "${PREFLIGHT_NO_UPDATE_CHECK:-}" ] && exit 0

# 2. Persistent opt-out file.
NO_CHECK_FILE="$HOME/.claude/.preflight-no-update-check"
[ -f "$NO_CHECK_FILE" ] && exit 0

# 3. Throttle: at most one check per day. No timestamp yet is not a reason to
# skip; a garbage timestamp is treated the same way (check runs).
THROTTLE_FILE="$HOME/.claude/.preflight-update-check"
if [ -f "$THROTTLE_FILE" ]; then
	now="$(date +%s 2>/dev/null)" || now=""
	ts="$(cat -- "$THROTTLE_FILE" 2>/dev/null | tr -d '\000')"
	case "$ts" in ''|*[!0-9]*) ts="" ;; esac
	if [ -n "$now" ] && [ -n "$ts" ]; then
		age=$(( now - ts ))
		[ "$age" -lt 86400 ] && exit 0
	fi
fi

# 4. Read local plugin identity/version.
PLUGIN_JSON="$HERE/../.claude-plugin/plugin.json"
[ -r "$PLUGIN_JSON" ] || exit 0

LOCAL_VERSION="$(jq -r '.version // empty' "$PLUGIN_JSON" 2>/dev/null)"
LOCAL_NAME="$(jq -r '.name // empty' "$PLUGIN_JSON" 2>/dev/null)"
REPOSITORY="$(jq -r '.repository // empty' "$PLUGIN_JSON" 2>/dev/null)"
[ -n "$LOCAL_VERSION" ] && [ -n "$LOCAL_NAME" ] && [ -n "$REPOSITORY" ] || exit 0

# 5. repository must be a plain https://github.com/OWNER/REPO URL (optional
# .git suffix / trailing slash); anything else, we don't know how to check.
case "$REPOSITORY" in
	https://github.com/*/*) : ;;
	*) exit 0 ;;
esac
OWNER_REPO="${REPOSITORY#https://github.com/}"
OWNER_REPO="${OWNER_REPO%.git}"
OWNER_REPO="${OWNER_REPO%/}"
case "$OWNER_REPO" in
	*/*/*) exit 0 ;;
	*/*) : ;;
	*) exit 0 ;;
esac

# 6. Fetch the marketplace manifest (or read it from the test seam). The
# throttle timestamp is written after this attempt regardless of outcome, so
# an offline machine only ever retries once a day, not every session.
MANIFEST=""
FETCH_OK=1
if [ -n "${PREFLIGHT_UPDATE_MANIFEST:-}" ]; then
	MANIFEST="$(cat -- "$PREFLIGHT_UPDATE_MANIFEST" 2>/dev/null | tr -d '\000')"
	FETCH_OK=${PIPESTATUS[0]}
	[ -n "$MANIFEST" ] || FETCH_OK=1
elif command -v curl >/dev/null 2>&1; then
	MANIFEST_URL="https://raw.githubusercontent.com/$OWNER_REPO/HEAD/.claude-plugin/marketplace.json"
	MANIFEST="$(curl -fsS --max-time 3 -- "$MANIFEST_URL" 2>/dev/null | tr -d '\000')"
	FETCH_OK=${PIPESTATUS[0]}
fi

mkdir -p "$HOME/.claude" 2>/dev/null
date +%s > "$THROTTLE_FILE" 2>/dev/null

[ "$FETCH_OK" -eq 0 ] && [ -n "$MANIFEST" ] || exit 0

# 7. Compare versions; only speak up when the remote is strictly newer.
REMOTE_VERSION="$(printf '%s' "$MANIFEST" | jq -r --arg name "$LOCAL_NAME" \
	'(.plugins // [])[] | select(.name == $name) | .version // empty' 2>/dev/null | head -n 1 | tr -d '\000')"
[ -n "$REMOTE_VERSION" ] || exit 0

if preflight_version_gt "$REMOTE_VERSION" "$LOCAL_VERSION"; then
	{
		printf 'preflight: version %s is available (installed: %s)\n' "$REMOTE_VERSION" "$LOCAL_VERSION"
		printf 'preflight:   claude plugin marketplace update preflight && claude plugin update preflight@preflight\n'
		printf 'preflight:   silence this with PREFLIGHT_NO_UPDATE_CHECK=1\n'
	} >&2
fi

exit 0

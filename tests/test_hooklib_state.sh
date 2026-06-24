#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../plugin/hooks/preflight-hooklib.sh"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

tmp="$(mktemp -d)"
f="$tmp/doc.md"; printf 'hello' > "$f"
h="$(preflight_hash "$f")"
[ -n "$h" ] && ok "hash non-empty" || bad "hash empty (no sha tool?)"

state="$tmp/.preflight-reviewed"
preflight_already_reviewed "$state" "$f" "$h" && bad "not reviewed yet but reported reviewed" || ok "unknown hash -> not reviewed"
printf '%s\t%s\n' "$h" "$f" > "$state"
preflight_already_reviewed "$state" "$f" "$h" && ok "known hash -> reviewed" || bad "known hash not recognized"
preflight_already_reviewed "$state" "$f" "" && bad "empty hash treated as reviewed" || ok "empty hash -> fail-open"

lock="$tmp/.preflight-running"
preflight_is_locked "$lock" && bad "no lock file but locked" || ok "absent lock -> unlocked"
date +%s > "$lock"
preflight_is_locked "$lock" && ok "fresh lock -> locked" || bad "fresh lock not detected"
echo $(( $(date +%s) - 99999 )) > "$lock"
preflight_is_locked "$lock" && bad "stale lock still locked" || ok "stale lock -> unlocked (fail-open)"
printf 'garbage' > "$lock"
preflight_is_locked "$lock" && bad "garbage lock locked" || ok "garbage lock -> unlocked"
printf '%s\t%s\n' "$h" "${f}2" > "$state"
preflight_already_reviewed "$state" "$f" "$h" && bad "prefix path falsely matched" || ok "prefix path -> not reviewed"
rm -rf "$tmp"
exit $fail

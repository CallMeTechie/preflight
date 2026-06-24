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

# preflight_record_reviewed: second call for same path replaces first entry
state2="$tmp/.preflight-reviewed2"
preflight_record_reviewed "$state2" "$f" "hash1"
preflight_record_reviewed "$state2" "$f" "hash2"
lines="$(grep -c '' "$state2" 2>/dev/null || echo 0)"
[ "$lines" -eq 1 ] && ok "record_reviewed: one entry per path" || bad "record_reviewed: expected 1 line, got $lines"
grep -qF "hash2" "$state2" && ok "record_reviewed: latest hash present" || bad "record_reviewed: latest hash missing"
grep -qF "hash1" "$state2" && bad "record_reviewed: old hash still present" || ok "record_reviewed: old hash replaced"

# preflight_path_ok: control chars rejected; clean paths accepted
preflight_path_ok "$tmp/x"$'\n'"y" && bad "path_ok: newline path accepted" || ok "path_ok: newline path rejected"
preflight_path_ok "$tmp/clean.md" && ok "path_ok: clean path accepted" || bad "path_ok: clean path rejected"

# preflight_is_locked: future timestamp must be treated as locked (clock jump)
echo $(( $(date +%s) + 600 )) > "$lock"
preflight_is_locked "$lock" && ok "future timestamp -> locked" || bad "future timestamp not treated as locked"

# preflight_record_reviewed: path with literal backslash must deduplicate (ENVIRON guard, not awk -v)
state3="$tmp/.preflight-reviewed3"
bp="$tmp/a\\b.md"
preflight_record_reviewed "$state3" "$bp" "hashA"
preflight_record_reviewed "$state3" "$bp" "hashB"
lines_bp="$(grep -c '' "$state3" 2>/dev/null || echo 0)"
[ "$lines_bp" -eq 1 ] && ok "record_reviewed: backslash path -> one entry" || bad "record_reviewed: backslash path -> expected 1 line, got $lines_bp"
grep -qF "hashB" "$state3" && ok "record_reviewed: backslash path -> latest hash present" || bad "record_reviewed: backslash path -> latest hash missing"
grep -qF "hashA" "$state3" && bad "record_reviewed: backslash path -> old hash still present" || ok "record_reviewed: backslash path -> old hash replaced"

# preflight_record_reviewed: control-char path must fail (guard) and must not write
state4="$tmp/.preflight-reviewed4"
preflight_record_reviewed "$state4" "$f" "clean_hash"  # seed one clean entry
lines_before="$(grep -c '' "$state4" 2>/dev/null || echo 0)"
preflight_record_reviewed "$state4" "$tmp/x"$'\n'"y" "$h"
rc_bad=$?
[ "$rc_bad" -ne 0 ] && ok "record_reviewed: control-char path -> non-zero return" || bad "record_reviewed: control-char path -> expected non-zero return"
lines_after="$(grep -c '' "$state4" 2>/dev/null || echo 0)"
[ "$lines_after" -eq "$lines_before" ] && ok "record_reviewed: control-char path -> no line written" || bad "record_reviewed: control-char path -> line count changed from $lines_before to $lines_after"

rm -rf "$tmp"
exit $fail

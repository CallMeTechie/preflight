#!/usr/bin/env bash
# Tests for the SessionStart hook that notifies about a newer preflight version.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
LIB="$HERE/../plugin/hooks/preflight-hooklib.sh"
HOOK="$HERE/../plugin/hooks/check-plugin-update.sh"
. "$LIB"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

# --- preflight_version_gt, direct ---------------------------------------
# Trailing-zero style must never matter (a difference between plugin.json and
# marketplace.json here must not make the hook cry wolf), and numeric
# comparison must not degrade to lexical comparison.

preflight_version_gt "0.10.0" "0.2.0" && ok "version_gt: 0.10.0 > 0.2.0 (numeric, not lexical)" || bad "version_gt: 0.10.0 > 0.2.0"
preflight_version_gt "0.3.0" "0.2.9" && ok "version_gt: 0.3.0 > 0.2.9" || bad "version_gt: 0.3.0 > 0.2.9"
preflight_version_gt "0.2.0" "0.3.0" && bad "version_gt: 0.2.0 > 0.3.0 (should be false)" || ok "version_gt: 0.2.0 not > 0.3.0"
preflight_version_gt "0.2.0" "0.2.0" && bad "version_gt: 0.2.0 > 0.2.0 (should be false)" || ok "version_gt: 0.2.0 not > 0.2.0"
preflight_version_gt "1.0.0" "1.0" && bad "version_gt: 1.0.0 > 1.0 (trailing zero must not count, should be false)" || ok "version_gt: 1.0.0 not > 1.0 (trailing zero doesn't count)"
preflight_version_gt "1.0" "1.0.0" && bad "version_gt: 1.0 > 1.0.0 (should be false)" || ok "version_gt: 1.0 not > 1.0.0 (symmetric)"
preflight_version_gt "0.2.0" "0.2" && bad "version_gt: 0.2.0 > 0.2 (trailing zero must not count, should be false)" || ok "version_gt: 0.2.0 not > 0.2 (trailing zero doesn't count)"
preflight_version_gt "0.2" "0.2.0" && bad "version_gt: 0.2 > 0.2.0 (should be false)" || ok "version_gt: 0.2 not > 0.2.0 (symmetric)"
# Non-numeric field: reads as 0, never crashes, never accidentally wins.
preflight_version_gt "1.2.0-rc1" "1.2.0" && bad "version_gt: 1.2.0-rc1 > 1.2.0 (non-numeric field should read as 0, should be false)" || ok "version_gt: non-numeric field reads as 0, doesn't crash or win"

# --- hook, end to end -----------------------------------------------------
# HOME is redirected into the sandbox for every run below so neither the
# throttle file nor an opt-out file of the real user is ever touched.

fresh_home() {
	tmp="$(mktemp -d)"
	mkdir -p "$tmp/.claude"
	printf '%s' "$tmp"
}

manifest_with_version() {
	# $1 = dir, $2 = version -> path to a manifest file declaring that version
	# for the "preflight" plugin.
	local dir="$1" version="$2" f
	f="$dir/manifest.json"
	printf '{"plugins":[{"name":"preflight","version":"%s"}]}' "$version" > "$f"
	printf '%s' "$f"
}

old_ts() { echo $(( $(date +%s) - 200000 )); }   # well past the 86400s throttle

# The installed version is read from the manifest the hook itself reads. Hard-coding
# it here made this file go red on every version bump, which trains the reader to
# "fix" a real regression by editing the expectation.
INSTALLED="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$HERE/../plugin/.claude-plugin/plugin.json" | head -1)"
[ -n "$INSTALLED" ] && ok "installed version read from plugin.json ($INSTALLED)" \
	|| bad "could not read the installed version from plugin.json"

# (1) Newer version in manifest -> stderr message with both version numbers, stdout empty.
h="$(fresh_home)"
m="$(manifest_with_version "$h" "9.9.9")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && ok "newer version: stdout empty" || bad "newer version: stdout not empty ($out)"
printf '%s' "$err" | grep -q "9.9.9" && printf '%s' "$err" | grep -q "$INSTALLED" && \
	ok "newer version: stderr names both versions" || bad "newer version: stderr missing a version ($err)"
rm -rf "$h"

# (2) Equal version -> no output at all.
h="$(fresh_home)"
m="$(manifest_with_version "$h" "$INSTALLED")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && [ -z "$err" ] && ok "equal version: silent" || bad "equal version: unexpected output (out='$out' err='$err')"
rm -rf "$h"

# (3) Older version -> no output at all.
h="$(fresh_home)"
m="$(manifest_with_version "$h" "0.0.1")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && [ -z "$err" ] && ok "older version: silent" || bad "older version: unexpected output (out='$out' err='$err')"
rm -rf "$h"

# (4) PREFLIGHT_NO_UPDATE_CHECK set -> silent AND no throttle file written.
h="$(fresh_home)"
m="$(manifest_with_version "$h" "9.9.9")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" PREFLIGHT_NO_UPDATE_CHECK=1 bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && [ -z "$err" ] && ok "env opt-out: silent" || bad "env opt-out: unexpected output"
[ ! -f "$h/.claude/.preflight-update-check" ] && ok "env opt-out: no throttle file written" || bad "env opt-out: throttle file was written"
rm -rf "$h"

# (5) Opt-out file present -> silent, no throttle write.
h="$(fresh_home)"
: > "$h/.claude/.preflight-no-update-check"
m="$(manifest_with_version "$h" "9.9.9")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && [ -z "$err" ] && ok "opt-out file: silent" || bad "opt-out file: unexpected output"
[ ! -f "$h/.claude/.preflight-update-check" ] && ok "opt-out file: no throttle file written" || bad "opt-out file: throttle file was written"
rm -rf "$h"

# (6) Fresh throttle timestamp -> silent, no fetch attempted (even though the
# manifest declares a newer version, it must never be consulted).
h="$(fresh_home)"
date +%s > "$h/.claude/.preflight-update-check"
m="$(manifest_with_version "$h" "9.9.9")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && [ -z "$err" ] && ok "fresh throttle: silent (no fetch)" || bad "fresh throttle: unexpected output (should have skipped fetch)"
rm -rf "$h"

# (7) Old throttle timestamp -> check runs (newer manifest -> message).
h="$(fresh_home)"
old_ts > "$h/.claude/.preflight-update-check"
m="$(manifest_with_version "$h" "9.9.9")"
out="$(HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" 2>"$h/err.txt")"
err="$(cat "$h/err.txt")"
[ -z "$out" ] && printf '%s' "$err" | grep -q "9.9.9" && ok "old throttle: check runs" || bad "old throttle: check did not run (err='$err')"
rm -rf "$h"

# (8) Unreadable/broken manifest -> silent, exit 0.
h="$(fresh_home)"
old_ts > "$h/.claude/.preflight-update-check"
broken="$h/broken.json"
printf 'not { valid json' > "$broken"
HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$broken" bash -c 'printf "{}" | bash "$0"' "$HOOK" >"$h/out.txt" 2>"$h/err.txt"
rc=$?
out="$(cat "$h/out.txt")"; err="$(cat "$h/err.txt")"
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] && ok "broken manifest: silent, exit 0" || bad "broken manifest: rc=$rc out='$out' err='$err'"
rm -rf "$h"

# (9) Missing manifest seam file (simulates a failed fetch) -> silent, exit 0.
h="$(fresh_home)"
old_ts > "$h/.claude/.preflight-update-check"
HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$h/does-not-exist.json" bash -c 'printf "{}" | bash "$0"' "$HOOK" >"$h/out.txt" 2>"$h/err.txt"
rc=$?
out="$(cat "$h/out.txt")"; err="$(cat "$h/err.txt")"
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] && ok "missing manifest file: silent, exit 0" || bad "missing manifest file: rc=$rc out='$out' err='$err'"
[ -f "$h/.claude/.preflight-update-check" ] && ok "missing manifest file: throttle timestamp still written" || bad "missing manifest file: throttle not written"
rm -rf "$h"

# (10) Throttle file contains an embedded NUL byte (partially written file,
# zero-fill on crash recovery, or two sessions writing without locking) on an
# otherwise-silent branch (equal remote version). Must produce empty stdout
# AND empty stderr -- a stray "ignored null byte in input" warning from
# bash's own command substitution would fail this even though the exit code
# is still 0, which is why both streams are asserted, not just the exit code.
h="$(fresh_home)"
printf 'abc\000def' > "$h/.claude/.preflight-update-check"
m="$(manifest_with_version "$h" "$INSTALLED")"
HOME="$h" PREFLIGHT_UPDATE_MANIFEST="$m" bash -c 'printf "{}" | bash "$0"' "$HOOK" >"$h/out.txt" 2>"$h/err.txt"
rc=$?
out="$(cat "$h/out.txt")"; err="$(cat "$h/err.txt")"
[ "$rc" -eq 0 ] && [ -z "$out" ] && [ -z "$err" ] && ok "NUL byte in throttle file: silent (no bash warning), exit 0" || bad "NUL byte in throttle file: rc=$rc out='$out' err='$err'"
rm -rf "$h"

exit $fail

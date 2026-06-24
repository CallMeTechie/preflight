#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../plugin/hooks/preflight-hooklib.sh"
fail=0
assert_eq() { if [ "$1" != "$2" ]; then echo "FAIL: $3 (got '$1' want '$2')"; fail=1; else echo "ok: $3"; fi; }

assert_eq "$(preflight_detect_mode /x/docs/superpowers/specs/2026-06-24-foo-design.md)" "spec" "spec path"
assert_eq "$(preflight_detect_mode /x/docs/superpowers/plans/2026-06-24-foo.md)" "plan" "plan path"
assert_eq "$(preflight_detect_mode /x/docs/superpowers/specs/notes.md)" "" "specs dir but not -design.md"
assert_eq "$(preflight_detect_mode /x/src/main.rs)" "" "foreign path"

tmp="$(mktemp -d)"; mkdir -p "$tmp/proj/.git" "$tmp/proj/docs/superpowers/plans"
f="$tmp/proj/docs/superpowers/plans/2026-06-24-foo.md"; : > "$f"
assert_eq "$(preflight_find_root "$f" /fallback)" "$tmp/proj" "find root via .git"
assert_eq "$(preflight_find_root /nope/x.md /fallback)" "/fallback" "fallback when no marker"
rm -rf "$tmp"
exit $fail

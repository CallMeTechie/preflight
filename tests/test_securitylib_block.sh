#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../plugin/lib/preflight-securitylib.sh"
fail=0
assert_eq() { if [ "$1" != "$2" ]; then echo "FAIL: $3 (got '$1' want '$2')"; fail=1; else echo "ok: $3"; fi; }

tmp="$(mktemp -d)"
B='<!-- preflight:security:begin -->'
E='<!-- preflight:security:end -->'

mk() { printf '%s\n' "$@" > "$tmp/case.md"; }
code() { preflight_security_block_state "$tmp/case.md"; printf '%s' "$?"; }

mk "# Spec" "text" "$B" "table" "$E" "more"
assert_eq "$(code)" "0" "well-formed block -> 0"

mk "# Spec" "text" "no markers here"
assert_eq "$(code)" "1" "no markers -> 1"

mk "# Spec" "$B" "orphan begin"
assert_eq "$(code)" "2" "begin only -> 2"

mk "# Spec" "orphan end" "$E"
assert_eq "$(code)" "2" "end only -> 2"

mk "# Spec" "$B" "a" "$E" "$B" "b" "$E"
assert_eq "$(code)" "2" "duplicated block -> 2"

mk "# Spec" "$E" "reversed" "$B"
assert_eq "$(code)" "2" "end before begin -> 2"

# a spec that DOCUMENTS the format does not HAVE a block
mk "# Spec" '```markdown' "$B" "example" "$E" '```' "text"
assert_eq "$(code)" "1" "markers inside a fenced example do not count"

mk "# Spec" "prose mentioning \`$B\` and \`$E\` inline"
assert_eq "$(code)" "1" "markers inline in prose do not count"

mk "# Spec" '```' "$B" '```' "$B" "real" "$E"
assert_eq "$(code)" "0" "a fenced example next to a real block still resolves"

preflight_security_block_state "$tmp/does-not-exist.md"
assert_eq "$?" "3" "missing file -> 3, not a marker problem"

rm -rf "$tmp"
exit $fail

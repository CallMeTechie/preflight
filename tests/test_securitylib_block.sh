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

FIX="$HERE/fixtures"

preflight_security_block_state "$FIX/sample-spec-with-security-design.md"
assert_eq "$?" "0" "fixture with block -> 0"

preflight_security_facts_valid "$FIX/sample-spec-with-security-design.md"
assert_eq "$?" "0" "fixture facts are valid"

preflight_security_facts_valid "$FIX/sample-spec-invalid-facts-design.md"
assert_eq "$?" "1" "persistence=sqlite is rejected"

# a missing fact is as fatal as a wrong value
sed 's/ handles_pii=yes//' "$FIX/sample-spec-with-security-design.md" > "$tmp/missing.md"
preflight_security_facts_valid "$tmp/missing.md"
assert_eq "$?" "1" "missing fact is rejected"

# an unknown key is rejected
sed 's/handles_pii=yes/handles_pii=yes bogus_key=yes/' "$FIX/sample-spec-with-security-design.md" > "$tmp/bogus.md"
preflight_security_facts_valid "$tmp/bogus.md"
assert_eq "$?" "1" "unknown key is rejected"

# consistency: renders_html=yes with an api-only surface
sed 's/network_surface=http-html/network_surface=http-api/' "$FIX/sample-spec-with-security-design.md" > "$tmp/inconsistent.md"
preflight_security_facts_valid "$tmp/inconsistent.md"
assert_eq "$?" "1" "renders_html=yes with http-api is rejected"

# a block without a facts comment cannot be derived from
sed '/<!-- facts:/,/-->/d' "$FIX/sample-spec-with-security-design.md" > "$tmp/nofacts.md"
preflight_security_facts_valid "$tmp/nofacts.md"
assert_eq "$?" "1" "block without facts comment is rejected"

# a facts example quoted ABOVE the block must not win over the real one
{ printf '%s\n\n' 'Format: `<!-- facts: network_surface=none has_accounts=no -->`'
  cat "$FIX/sample-spec-with-security-design.md"; } > "$tmp/quoted.md"
preflight_security_facts_valid "$tmp/quoted.md"
assert_eq "$?" "0" "a quoted facts example above the block is ignored"

# a glob in the facts comment must never be expanded against the working directory
sed 's/persistence=sql/persistence=s*/' "$FIX/sample-spec-with-security-design.md" > "$tmp/glob.md"
( cd "$tmp" && : > 'persistence=sql'
  preflight_security_facts_valid "$tmp/glob.md"
  exit $? )
assert_eq "$?" "1" "a glob in the facts comment is not expanded"

rm -rf "$tmp"
exit $fail

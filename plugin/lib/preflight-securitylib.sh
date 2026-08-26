# Domain helpers for the preflight security profiler.
# Sourced by the skill's profiler and by the security tests.
# Not used by any hook — the hook library stays free of domain knowledge.

# Line numbers of the security marker <kind> (begin|end) in <file>, one per line.
# Markers inside fenced code blocks and markers embedded in a sentence do NOT
# count: a spec that *documents* the format is not a spec that *has* a block.
# Without this the plugin's own spec classifies as damaged — verified: three
# matches, one fenced example and two prose mentions.
preflight_marker_lines() {
	awk -v kind="$2" '
		{ line = $0; sub(/[[:space:]]+$/, "", line); sub(/^[[:space:]]+/, "", line) }
		line ~ /^(```|~~~)/ { fence = !fence; next }
		fence { next }
		line == "<!-- preflight:security:" kind " -->" { print NR }
	' "$1" 2>/dev/null
}

# Classify the security block in <file>. No stdout; the exit code is the answer.
#   0 = exactly one begin and one end, begin before end -> profiler may replace
#   1 = neither marker present                          -> profiler writes fresh
#   2 = anything else (one-sided, duplicated, reversed) -> abort, block damaged
#   3 = file missing or unreadable                      -> abort, wrong path
# Not a predicate: always branch on all four codes, never on success/failure.
# Never collapse 2 into 1 — replacing between damaged markers eats spec content.
preflight_security_block_state() {
	local file="$1" lb le nb ne
	[ -f "$file" ] && [ -r "$file" ] || return 3
	lb="$(preflight_marker_lines "$file" begin)"
	le="$(preflight_marker_lines "$file" end)"
	nb="$(printf '%s' "$lb" | grep -c . || :)"
	ne="$(printf '%s' "$le" | grep -c . || :)"
	if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then return 1; fi
	if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then return 2; fi
	[ "$lb" -lt "$le" ] || return 2
	return 0
}

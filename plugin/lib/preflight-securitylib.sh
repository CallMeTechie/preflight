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

# Line numbers of the security marker <kind> in <file> WITHOUT fence filtering.
# Only used to detect a block that an unterminated fence would otherwise hide;
# never use it to locate a block — a documented example would count as one.
preflight_marker_lines_raw() {
	awk -v kind="$2" '
		{ line = $0; sub(/[[:space:]]+$/, "", line); sub(/^[[:space:]]+/, "", line) }
		line == "<!-- preflight:security:" kind " -->" { print NR }
	' "$1" 2>/dev/null
}

# Return 0 if a code fence is still open at end of <file>.
preflight_fence_open_at_eof() {
	awk '
		{ line = $0; sub(/[[:space:]]+$/, "", line); sub(/^[[:space:]]+/, "", line) }
		line ~ /^(```|~~~)/ { fence = !fence }
		END { exit fence ? 0 : 1 }
	' "$1" 2>/dev/null
}

# Classify the security block in <file>. No stdout; the exit code is the answer.
#   0 = exactly one begin and one end, begin before end -> profiler may replace
#   1 = neither marker present                          -> profiler writes fresh
#   2 = anything else (one-sided, duplicated, reversed, or a real block hidden
#       by an unterminated fence)                        -> abort, block damaged
#   3 = file missing or unreadable                      -> abort, wrong path
# Not a predicate: always branch on all four codes, never on success/failure.
# Never collapse 2 into 1 — replacing between damaged markers eats spec content.
preflight_security_block_state() {
	local file="$1" lb le nb ne rb re
	[ -f "$file" ] && [ -r "$file" ] || return 3
	lb="$(preflight_marker_lines "$file" begin)"
	le="$(preflight_marker_lines "$file" end)"
	nb="$(printf '%s' "$lb" | grep -c . || :)"
	ne="$(printf '%s' "$le" | grep -c . || :)"
	# An unterminated fence swallows every marker below it. Without this the
	# profiler would see "no block" and APPEND a second one below the first.
	# Only a fence left open at EOF can do that, so a properly closed example
	# block keeps classifying as before.
	if preflight_fence_open_at_eof "$file"; then
		rb="$(preflight_marker_lines_raw "$file" begin | grep -c . || :)"
		re="$(preflight_marker_lines_raw "$file" end | grep -c . || :)"
		if [ "$((rb + re))" -gt "$((nb + ne))" ]; then return 2; fi
	fi
	if [ "$nb" -eq 0 ] && [ "$ne" -eq 0 ]; then return 1; fi
	if [ "$nb" -ne 1 ] || [ "$ne" -ne 1 ]; then return 2; fi
	[ "$lb" -lt "$le" ] || return 2
	return 0
}

# The facts token string from the block in <file>, or exit 1. Only the comment
# *between* the markers counts: a spec may quote the format in its prose, and
# the first <!-- facts: in the file would then be an example, not the state.
# All whitespace is squeezed to single spaces: the format separates tokens by
# whitespace, so a tab-indented continuation line is legal, and preflight_fact_get
# matches on a literal space.
preflight_security_facts_raw() {
	local file="$1" lb le
	lb="$(preflight_marker_lines "$file" begin | head -1)"
	le="$(preflight_marker_lines "$file" end | head -1)"
	[ -n "$lb" ] && [ -n "$le" ] && [ "$lb" -lt "$le" ] || return 1
	sed -n "${lb},${le}p" "$file" \
	  | awk '/<!-- facts:/{f=1} f{print} f && /-->/{exit}' \
	  | sed -e 's/.*<!-- facts://' -e 's/-->.*//' | tr '\n' ' ' \
	  | tr -s '[:space:]' ' '
}

# Allowed values for one of the eleven security facts, space separated.
# Empty output means the key is not a defined fact.
preflight_fact_values() {
	case "$1" in
		network_surface)      printf 'none http-api http-html both' ;;
		has_accounts)         printf 'yes no' ;;
		auth_method)          printf 'own-password delegated api-key none' ;;
		has_privilege_levels) printf 'yes no' ;;
		session_transport)    printf 'cookie bearer-header none' ;;
		has_owned_data)       printf 'yes no' ;;
		is_multi_tenant)      printf 'yes no' ;;
		persistence)          printf 'sql nosql files none' ;;
		renders_html)         printf 'yes no' ;;
		accepts_uploads)      printf 'yes no' ;;
		handles_pii)          printf 'yes no' ;;
		*)                    printf '' ;;
	esac
}

# Look up one key in a whitespace separated list of key=value tokens.
# Splitting-free on purpose: a value holding * or ? would otherwise be glob-
# expanded against the working directory.
preflight_fact_get() {
	local rest=" $1 " val
	case "$rest" in
		*" $2="*) rest="${rest#*" $2="}"; val="${rest%%[[:space:]]*}"
		          printf '%s' "$val"; return 0 ;;
	esac
	return 1
}

# Return 0 if the facts comment inside the security block carries exactly the
# eleven defined keys, every value is allowed, and all consistency conditions
# hold. Never guesses, never fills in a default: a silently completed fact
# deletes a required row without anyone seeing it.
# Precondition: the caller has already checked preflight_security_block_state —
# this function reads between the FIRST begin and the FIRST end and therefore
# returns 0 on a duplicated (state 2) block whose first block happens to be valid.
preflight_security_facts_valid() {
	local file="$1" raw tok k v allowed key found n
	raw="$(preflight_security_facts_raw "$file")" || return 1
	case "$raw" in *[![:space:]]*) ;; *) return 1 ;; esac
	# Glob characters can never appear in a valid value. Reject them before any
	# word splitting, so the result can never depend on the working directory:
	# 'persistence=s*' next to a file named 'persistence=sql' would otherwise
	# expand into a valid token.
	case "$raw" in *[*?[]*) return 1 ;; esac
	# Exactly eleven tokens, no more, no less. A duplicated key (e.g. two
	# 'persistence=' tokens with conflicting values) would otherwise pass the
	# per-token loop unnoticed and preflight_fact_get would silently pick the
	# first one, which is exactly the guessing this function refuses to do.
	set -- $raw; n="$#"
	[ "$n" -eq 11 ] || return 1

	for tok in $raw; do
		case "$tok" in *=*) ;; *) return 1 ;; esac
		k="${tok%%=*}"; v="${tok#*=}"
		allowed="$(preflight_fact_values "$k")"
		[ -n "$allowed" ] || return 1
		case " $allowed " in *" $v "*) ;; *) return 1 ;; esac
	done

	for key in network_surface has_accounts auth_method has_privilege_levels \
	           session_transport has_owned_data is_multi_tenant persistence \
	           renders_html accepts_uploads handles_pii; do
		found="$(preflight_fact_get "$raw" "$key")" || return 1
		[ -n "$found" ] || return 1
	done

	if [ "$(preflight_fact_get "$raw" renders_html)" = "yes" ]; then
		case "$(preflight_fact_get "$raw" network_surface)" in
			http-html|both) ;;
			*) return 1 ;;
		esac
	fi
	if [ "$(preflight_fact_get "$raw" network_surface)" = "none" ]; then
		[ "$(preflight_fact_get "$raw" session_transport)" = "none" ] || return 1
		[ "$(preflight_fact_get "$raw" renders_html)" = "no" ]        || return 1
		[ "$(preflight_fact_get "$raw" accepts_uploads)" = "no" ]     || return 1
	fi
	if [ "$(preflight_fact_get "$raw" has_accounts)" = "no" ]; then
		case "$(preflight_fact_get "$raw" auth_method)" in
			api-key|none) ;;
			*) return 1 ;;
		esac
	fi
	if [ "$(preflight_fact_get "$raw" is_multi_tenant)" = "yes" ]; then
		[ "$(preflight_fact_get "$raw" has_owned_data)" = "yes" ] || return 1
	fi
	return 0
}

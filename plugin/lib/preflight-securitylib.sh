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

# The facts token string from the block in <file>, or exit 1. Only the comment
# *between* the markers counts: a spec may quote the format in its prose, and
# the first <!-- facts: in the file would then be an example, not the state.
preflight_security_facts_raw() {
	local file="$1" lb le
	lb="$(preflight_marker_lines "$file" begin | head -1)"
	le="$(preflight_marker_lines "$file" end | head -1)"
	[ -n "$lb" ] && [ -n "$le" ] && [ "$lb" -lt "$le" ] || return 1
	sed -n "${lb},${le}p" "$file" \
	  | awk '/<!-- facts:/{f=1} f{print} f && /-->/{exit}' \
	  | sed -e 's/.*<!-- facts://' -e 's/-->.*//' | tr '\n' ' '
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
preflight_security_facts_valid() {
	local file="$1" raw tok k v allowed key found
	raw="$(preflight_security_facts_raw "$file")" || return 1
	case "$raw" in *[![:space:]]*) ;; *) return 1 ;; esac
	# Glob characters can never appear in a valid value. Reject them before any
	# word splitting, so the result can never depend on the working directory:
	# 'persistence=s*' next to a file named 'persistence=sql' would otherwise
	# expand into a valid token.
	case "$raw" in *[*?[]*) return 1 ;; esac

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

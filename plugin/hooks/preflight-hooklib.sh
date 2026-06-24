# Pure helper functions for the preflight PostToolUse hook.
# Sourced by detect-spec-plan-write.sh and by tests. No side effects on source.

# Echo "spec" | "plan" | "" for a given file path.
preflight_detect_mode() {
	case "$1" in
		*/docs/superpowers/specs/*-design.md) printf 'spec' ;;
		*/docs/superpowers/plans/*.md)        printf 'plan' ;;
		*) printf '' ;;
	esac
}

# Walk up from the file's directory to find a project root
# (dir containing .git or .claude); fall back to $2.
preflight_find_root() {
	local dir
	dir="$(CDPATH= cd -- "$(dirname -- "$1")" 2>/dev/null && pwd)" || { printf '%s' "$2"; return; }
	while [ -n "$dir" ] && [ "$dir" != "/" ]; do
		if [ -d "$dir/.git" ] || [ -d "$dir/.claude" ]; then
			printf '%s' "$dir"; return
		fi
		dir="$(dirname -- "$dir")"
	done
	printf '%s' "$2"
}

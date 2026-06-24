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

# SHA-256 of a file's contents (empty string if no tool available).
preflight_hash() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 -- "$1" 2>/dev/null | cut -d' ' -f1
	else
		printf ''
	fi
}

# Return 0 if <hash> for <path> is already recorded in the state file.
# Empty hash -> return 1 (fail-open: treat as not reviewed, so we nudge).
preflight_already_reviewed() {
	local state="$1" path="$2" hash="$3" line
	[ -n "$hash" ] || return 1
	[ -f "$state" ] || return 1
	line="$(printf '%s\t%s' "$hash" "$path")"
	grep -qFx -- "$line" "$state" 2>/dev/null
}

# Return 0 if a non-stale lock exists. Stale threshold default 1800s.
# Lock content is a unix timestamp; garbage or too-old -> not locked.
preflight_is_locked() {
	local lock="$1" threshold="${2:-1800}" now ts age
	[ -f "$lock" ] || return 1
	now="$(date +%s 2>/dev/null)" || return 1
	ts="$(cat -- "$lock" 2>/dev/null)"
	case "$ts" in ''|*[!0-9]*) return 1 ;; esac
	age=$(( now - ts ))
	[ "$age" -ge 0 ] && [ "$age" -lt "$threshold" ]
}

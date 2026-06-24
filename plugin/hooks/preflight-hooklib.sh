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
	path="$(preflight_canon_path "$path")"
	[ -n "$hash" ] || return 1
	[ -f "$state" ] || return 1
	line="$(printf '%s\t%s' "$hash" "$path")"
	grep -qFx -- "$line" "$state" 2>/dev/null
}

# Record <hash> for <path> in the state file, atomically replacing any
# previous entry for the same path (prevents unbounded growth + stale hashes).
preflight_record_reviewed() {
	local state="$1" path="$2" hash="$3" tmp
	preflight_path_ok "$path" || return 1
	path="$(preflight_canon_path "$path")"
	tmp="$(mktemp "$(dirname -- "$state")/.preflight-tmp.XXXXXX")" || return 1
	if [ -f "$state" ]; then
		_PREFLIGHT_PATH="$path" awk -F'\t' '$2 != ENVIRON["_PREFLIGHT_PATH"]' "$state" > "$tmp"
	fi
	printf '%s\t%s\n' "$hash" "$path" >> "$tmp"
	mv -- "$tmp" "$state"
}

# Return 0 if the path is safe (contains no control characters). Control
# chars in a path can split grep -F patterns and corrupt the state file.
preflight_path_ok() {
	case "$1" in
		*[[:cntrl:]]*) return 1 ;;
		*) return 0 ;;
	esac
}

# Canonicalize a path to a normalized absolute form (resolves ./, ../, trailing
# slash, and existing symlinks; does not require the path to exist). Falls back
# to the original string if realpath is unavailable.
preflight_canon_path() {
	realpath -m -- "$1" 2>/dev/null || printf '%s' "$1"
}

# Return 0 if a non-stale lock exists. Stale threshold default 1800s.
# Lock content is a unix timestamp; garbage or too-old -> not locked.
# A future timestamp (clock jump) is treated as locked, not unlocked.
preflight_is_locked() {
	local lock="$1" threshold="${2:-1800}" now ts age
	[ -f "$lock" ] || return 1
	now="$(date +%s 2>/dev/null)" || return 1
	ts="$(cat -- "$lock" 2>/dev/null)"
	case "$ts" in ''|*[!0-9]*) return 1 ;; esac
	age=$(( now - ts ))
	[ "$age" -lt "$threshold" ]
}

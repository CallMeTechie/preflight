#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../plugin/hooks/detect-spec-plan-write.sh"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

tmp="$(mktemp -d)"; mkdir -p "$tmp/proj/.git" "$tmp/proj/.claude" "$tmp/proj/docs/superpowers/plans"
plan="$tmp/proj/docs/superpowers/plans/2026-06-24-foo.md"; printf 'content' > "$plan"

run() { printf '{"tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$tmp/proj" | bash "$HOOK"; }

out="$(run "$plan")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("mode=plan")' >/dev/null && ok "plan write -> nudge plan" || bad "no plan nudge"

out="$(run "$tmp/proj/src/main.rs")"
[ -z "$out" ] && ok "foreign path -> no output" || bad "foreign path produced output"

# After recording the reviewed hash, no second nudge.
h="$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$plan"|cut -d' ' -f1; else shasum -a256 "$plan"|cut -d' ' -f1; fi)"
printf '%s\t%s\n' "$h" "$plan" > "$tmp/proj/.claude/.preflight-reviewed"
out="$(run "$plan")"
[ -z "$out" ] && ok "already-reviewed hash -> no nudge" || bad "debounce failed"

# Active lock suppresses nudge even for new content.
rm -f "$tmp/proj/.claude/.preflight-reviewed"; date +%s > "$tmp/proj/.claude/.preflight-running"
out="$(run "$plan")"
[ -z "$out" ] && ok "lock active -> no nudge" || bad "lock not honored"

# Control-char gate: newline embedded in a well-formed JSON path must fire the gate.
rm -f "$tmp/proj/.claude/.preflight-running"
bad_json="$(jq -n --arg fp "$plan"$'\n'"X" --arg cwd "$tmp/proj" '{"tool_input":{"file_path":$fp},"cwd":$cwd}')"
out="$(printf '%s' "$bad_json" | bash "$HOOK")"
[ -z "$out" ] && ok "newline in well-formed JSON -> gate fires, no output" || bad "newline in well-formed JSON: gate did not fire"

rm -rf "$tmp"
exit $fail

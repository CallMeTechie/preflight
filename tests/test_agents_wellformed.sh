#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
AGENTS="$HERE/../plugin/agents"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }
assert_eq() { if [ "$1" != "$2" ]; then echo "FAIL: $3 (got '$1' want '$2')"; fail=1; else echo "ok: $3"; fi; }

[ -d "$AGENTS" ] && ok "plugin/agents exists" || bad "plugin/agents missing"

for want in factchecker reviewer editor; do
  [ -f "$AGENTS/$want.md" ] && ok "$want.md present" || bad "$want.md missing"
done

for f in "$AGENTS"/*.md; do
  [ -f "$f" ] || continue
  base="$(basename "$f")"

  # frontmatter must open on line 1 and close again
  [ "$(head -1 "$f")" = "---" ] && ok "$base: frontmatter opens on line 1" \
    || bad "$base: line 1 is not '---'"
  [ "$(grep -c '^---$' "$f")" -ge 2 ] && ok "$base: frontmatter closes" \
    || bad "$base: no closing '---'"

  # name must match the filename
  name="$(sed -n 's/^name: *//p' "$f" | head -1)"
  assert_eq "$name" "${base%.md}" "$base: name matches filename"

  # description and model must be present, tools must be a single-line comma chain
  [ -n "$(sed -n 's/^description: *//p' "$f" | head -1)" ] && ok "$base: description set" \
    || bad "$base: description missing or empty"
  [ -n "$(sed -n 's/^model: *//p' "$f" | head -1)" ] && ok "$base: model set" \
    || bad "$base: model missing"
  tools="$(sed -n 's/^tools: *//p' "$f" | head -1)"
  [ -n "$tools" ] && ok "$base: tools set" || bad "$base: tools missing"
  case "$tools" in
    "") ;;
    *,*) ok "$base: tools is a comma chain" ;;
    *) bad "$base: tools must be a single-line comma chain, got '$tools'" ;;
  esac
  # a YAML block sequence would put tools on the following FRONTMATTER lines;
  # scanning the whole file would go red on any indented bullet in the body
  sed -n '2,/^---$/p' "$f" | grep -qE '^[[:space:]]+- ' \
    && bad "$base: frontmatter looks like a YAML block sequence" \
    || ok "$base: no block sequence"

  # body: not empty, at most 20 lines (mechanical brake against copying a mandate in)
  body_start="$(grep -n '^---$' "$f" | sed -n 2p | cut -d: -f1)"
  body_lines="$(sed -n "$((body_start + 1)),\$p" "$f" | grep -c '[^[:space:]]')"
  [ "$body_lines" -ge 1 ] && ok "$base: body not empty" || bad "$base: body is empty"
  [ "$body_lines" -le 20 ] && ok "$base: body <= 20 lines" \
    || bad "$base: body has $body_lines non-blank lines, limit is 20"
done

# exactly one agent may hold write tools, and it must be editor.md
# an empty result fails too: at least editor.md has to match
writers=""
for f in "$AGENTS"/*.md; do
  [ -f "$f" ] || continue
  if grep -qE '^tools:.*(\bWrite\b|\bEdit\b)' "$f"; then
    writers="$writers${writers:+,}$(basename "$f")"
  fi
done
assert_eq "$writers" "editor.md" "only editor.md carries write tools"

exit $fail

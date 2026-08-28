#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../plugin/lib/preflight-securitylib.sh"
M="$HERE/../plugin/skills/reviewing-spec-and-plan/references/security-matrix.md"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

[ -f "$M" ] && ok "security-matrix.md exists" || { bad "security-matrix.md missing"; exit 1; }

used_facts=""

# check_expr <label> <expression> <count_usage:yes|no>
# Verifies the trigger grammar: 'immer', or terms '<fact> = <value>' / '<fact> != <value>'
# joined by AND/OR, at most one paren level. Records referenced facts when asked to.
check_expr() {
  local label="$1" expr="$2" count="$3"
  local terms term k v allowed opens closes
  [ "$expr" = "immer" ] && return 0

  # parentheses: balanced, and not nested (the grammar allows one level)
  opens="$(printf '%s' "$expr" | tr -cd '(' | wc -c | tr -d ' ')"
  closes="$(printf '%s' "$expr" | tr -cd ')' | wc -c | tr -d ' ')"
  [ "$opens" -eq "$closes" ] || bad "$label: unbalanced parentheses"
  case "$expr" in *'('*'('*')'*')'*) bad "$label: nested parentheses" ;; esac

  # split on AND/OR without GNU sed: '\n' on the right-hand side is a GNU
  # extension, and BSD sed would insert a literal 'n' — leaving this test green
  # while it silently stops checking anything.
  terms="$(printf '%s' "$expr" | tr '()' '  ' | sed -e 's/ AND /|/g' -e 's/ OR /|/g' | tr '|' '\n')"
  while IFS= read -r term; do
    term="$(printf '%s' "$term" | sed -e 's/^ *//' -e 's/ *$//')"
    [ -n "$term" ] || continue
    case "$term" in
      *" != "*) k="${term%% != *}"; v="${term##* != }" ;;
      *" = "*)  k="${term%% = *}";  v="${term##* = }"  ;;
      *) bad "$label: term '$term' uses no supported operator"; continue ;;
    esac
    allowed="$(preflight_fact_values "$k")"
    if [ -z "$allowed" ]; then bad "$label: '$k' is not a defined fact"; continue; fi
    case " $allowed " in
      *" $v "*) ;;
      *) bad "$label: '$v' is not an allowed value for '$k'" ;;
    esac
    [ "$count" = "yes" ] && used_facts="$used_facts $k"
  done <<EOF_TERMS
$terms
EOF_TERMS
}

# --- rule rows: | SEC-XXX-NN | text | trigger | status |
rows="$(grep -E '^\| *SEC-[A-Z]+-[0-9]+ *\|' "$M" | sed 's/`//g')"
[ -n "$rows" ] && ok "matrix has rule rows" || bad "no rule rows found"

dupes="$(printf '%s\n' "$rows" | awk -F'|' '{gsub(/ /,"",$2); print $2}' | sort | uniq -d)"
[ -z "$dupes" ] && ok "rule IDs are unique" || bad "duplicate IDs: $dupes"

while IFS= read -r row; do
  [ -n "$row" ] || continue
  id="$(printf '%s' "$row"      | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')"
  trigger="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$4); print $4}')"
  status="$(printf '%s' "$row"  | awk -F'|' '{gsub(/^ +| +$/,"",$5); print $5}')"
  case "$status" in
    required|recommended) ;;
    *) bad "$id: status '$status' is not required|recommended" ;;
  esac
  check_expr "$id" "$trigger" yes
done <<EOF_ROWS
$rows
EOF_ROWS

# --- consistency conditions: | <fact> = <value> | <expression> |
conds="$(grep -E '^\| *[a-z_]+ = ' "$M" | sed 's/`//g')"
[ -n "$conds" ] && ok "matrix has consistency conditions" || bad "no consistency conditions found"

while IFS= read -r row; do
  [ -n "$row" ] || continue
  lhs="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')"
  rhs="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}')"
  # conditions must not count toward rule coverage: a fact used only here is still dead
  check_expr "cond($lhs) lhs" "$lhs" no
  check_expr "cond($lhs) rhs" "$rhs" no
done <<EOF_CONDS
$conds
EOF_CONDS

# --- the facts table must agree with preflight_fact_values (the single source of truth)
# Rows look like: | network_surface | none / http-api / http-html / both |
frows="$(grep -E '^\| *[a-z_]+ *\|' "$M" | sed 's/`//g')"
[ -n "$frows" ] && ok "matrix has a facts table" || bad "no facts table found"
table_keys=""
while IFS= read -r row; do
  [ -n "$row" ] || continue
  k="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$2); print $2}')"
  vals="$(printf '%s' "$row" | awk -F'|' '{gsub(/^ +| +$/,"",$3); print $3}' | tr '/' ' ')"
  allowed="$(preflight_fact_values "$k")"
  if [ -z "$allowed" ]; then bad "facts table lists '$k', which is not a defined fact"; continue; fi
  got="$(printf '%s\n' $vals | sort | tr '\n' ' ')"
  want="$(printf '%s\n' $allowed | sort | tr '\n' ' ')"
  [ "$got" = "$want" ] && ok "facts table matches hooklib for $k" \
    || bad "$k: table has '$got', hooklib has '$want'"
  table_keys="$table_keys $k"
done <<EOF_FROWS
$frows
EOF_FROWS

# --- counter-direction: every defined fact is referenced by at least one RULE
for key in network_surface has_accounts auth_method has_privilege_levels \
           session_transport has_owned_data is_multi_tenant persistence \
           renders_html accepts_uploads handles_pii; do
  case " $used_facts " in
    *" $key "*) ok "fact $key is used by a rule" ;;
    *) bad "fact $key is defined but no rule references it" ;;
  esac
  case " $table_keys " in
    *" $key "*) ;;
    *) bad "fact $key is defined in the hooklib but missing from the facts table" ;;
  esac
done

[ "$fail" -eq 0 ] && ok "matrix is well-formed"
exit $fail

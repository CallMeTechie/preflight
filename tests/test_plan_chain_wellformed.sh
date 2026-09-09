#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
C="$HERE/../plugin/skills/reviewing-spec-and-plan/references/plan-chain.md"
S="$HERE/../plugin/skills/reviewing-spec-and-plan/SKILL.md"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

for f in "$C" "$S"; do
  [ -f "$f" ] || { bad "$(basename "$f") missing"; exit 1; }
done
ok "plan-chain.md and SKILL.md exist"

# Stage 5 has to demand both per-task lines by name. Demanding only one leaves the
# other to the reviewer's taste, and a taste is not a deterministic classification.
stage5="$(sed -n '/^5\. \*\*Sequencing/,/^\*\*Stage 6/p' "$C")"
[ -n "$stage5" ] && ok "Stage 5 section found" || bad "Stage 5 section not found"
printf '%s' "$stage5" | grep -q '`Parallel:`' \
  && ok "Stage 5 demands a Parallel: line" || bad "Stage 5 never names the Parallel: line"
printf '%s' "$stage5" | grep -q '`Tests:`' \
  && ok "Stage 5 demands a Tests: line" || bad "Stage 5 never names the Tests: line"

# The block is the interface to Stage 6. Both columns must appear in the format spec.
printf '%s' "$stage5" | grep -q 'TASK-READINESS' \
  && ok "Stage 5 emits TASK-READINESS" || bad "Stage 5 defines no TASK-READINESS block"
printf '%s' "$stage5" | grep -qE 'tests: *present\|missing' \
  && ok "block spec carries the tests column" || bad "block spec lacks the tests column"
printf '%s' "$stage5" | grep -qE 'parallel: *present\|missing' \
  && ok "block spec carries the parallel column" || bad "block spec lacks the parallel column"

# Stage 6 must carry the matching rule, or the block is emitted and then ignored.
stage6="$(sed -n '/^\*\*Stage 6/,$p' "$C")"
printf '%s' "$stage6" | grep -q 'Rule on task readiness' \
  && ok "Stage 6 carries the task readiness rule" || bad "Stage 6 has no task readiness rule"
printf '%s' "$stage6" | grep -q 'tests: missing' \
  && ok "rule handles tests: missing" || bad "rule does not handle tests: missing"
printf '%s' "$stage6" | grep -q 'parallel: missing' \
  && ok "rule handles parallel: missing" || bad "rule does not handle parallel: missing"

# The point of the whole rule: it buys execution time back, so it must never spend it
# by blocking a plan. A future edit promoting this to No-Go would invert the intent.
printf '%s' "$stage6" | grep -qi 'never move the verdict\|Neither column ever moves the verdict' \
  && ok "rule states it never moves the verdict" \
  || bad "rule no longer states that it leaves the verdict alone"

# Sentinel for a plan without tasks: named in the format spec and honoured by the rule.
# Named in only one of the two means the reviewer emits a token Stage 6 cannot read.
for where in "Stage 5:$stage5" "Stage 6:$stage6"; do
  label="${where%%:*}"; body="${where#*:}"
  printf '%s' "$body" | grep -q 'KEINE-TASKLISTE' \
    && ok "$label knows the KEINE-TASKLISTE sentinel" \
    || bad "$label never mentions KEINE-TASKLISTE"
done

# The seam: Step 7 validates every finding adversarially before applying it. Unless
# TASK-READINESS is named in the exception, that pass can argue the deterministic
# findings away and the rule silently stops biting.
sed -n '/Exception, plan mode/,/^2\./p' "$S" | grep -q 'TASK-READINESS' \
  && ok "SKILL.md exempts TASK-READINESS from adversarial re-validation" \
  || bad "SKILL.md Step 7 does not exempt TASK-READINESS — the rule can be argued away"

[ "$fail" -eq 0 ] && ok "plan chain is well-formed"
exit $fail

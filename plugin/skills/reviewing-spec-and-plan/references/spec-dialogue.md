# Spec Review: Author↔Reviewer Dialogue (preflight:reviewer)

Simulate a review conversation between two engineers about the SPEC document.

- **Author:** defends decisions, explains trade-offs, proposes concrete replacement
  text when conceding.
- **Reviewer:** Senior; raises at least one substantive objection per round with
  concrete replacement text (not just a description).

Rules: Round label `### Round N — [Topic]`. The Author must defend at least once
per round instead of immediately conceding. Close resolved topics early:
`Consensus reached after N rounds.` Max rounds = passed in (default 5).

**Topic priority (in this order, skip empty topics):**
1. Completeness — placeholders, TBDs, undefined requirements, missing success criteria
2. Clarity / Ambiguity — requirements open to multiple interpretations, vague terms
3. Internal Consistency — contradicting sections; architecture ≠ feature description
4. Security-Profil — do the stored facts still match the system the spec
   describes? Is a `not-applicable` row missing its reason, or does the reason no
   longer hold? A drift finding ("the spec now describes uploads while `facts`
   says `accepts_uploads=no`") is reported, **never fixed**: it is not
   `fixable`, and its single recommendation is `/preflight-profile --redo`.
   Do **not** discuss the measures themselves — they are derived from the facts.
   Changing a measure means changing a fact or setting it to `not-applicable`,
   both through the profiler. Two ways to change the same row would make the
   block worthless as a yardstick.
5. Scope & YAGNI — too large for one plan? unnecessary features? decomposition needed?
6. Realism — use the passed-in fact list (`missing`/`deviating`)
7. Risks / Blind Spots — failure modes, optimistic shortcuts, edge cases

**Return (structured):** full transcript + `agreed_changes` (with concrete replacement
text + source location), `open_disagreements`, `action_items`
(priority Blocker/Important/Optional), `design_forks` (findings whose resolution
requires a real design decision with no objectively correct answer),
summary table (Topic | Rounds | Action Items).

# Spec Review: Author↔Reviewer Dialogue (cheap-reviewer)

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
4. Scope & YAGNI — too large for one plan? unnecessary features? decomposition needed?
5. Realism — use the passed-in fact list (`missing`/`deviating`)
6. Risks / Blind Spots — failure modes, optimistic shortcuts, edge cases

**Return (structured):** full transcript + `agreed_changes` (with concrete replacement
text + source location), `open_disagreements`, `action_items`
(priority Blocker/Important/Optional), `design_forks` (findings whose resolution
requires a real design decision with no objectively correct answer),
summary table (Topic | Rounds | Action Items).

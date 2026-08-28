# Manual Integration Tests — preflight Plugin

This guide verifies the skill path end-to-end against the demo fixtures.
Skill behavior is LLM-driven and cannot be automated; this is the honest
test boundary.

**Prerequisite:** The plugin is registered in Claude Code
(`~/.claude/plugins/preflight` or via `plugin add`).
The fixtures live under `tests/fixtures/` and that directory is intentionally
**not** under `docs/superpowers/` — the hook therefore does not trigger when
these fixtures are written.

---

## Scenario 1 — Spec Review

**Command:**
```
/preflight-spec tests/fixtures/sample-spec-design.md
```

**Expected behavior:**

1. The skill sets the lock `.claude/.preflight-running`.
2. A `preflight:factchecker` checks file references for existence.
3. A `preflight:reviewer` runs the author/reviewer dialog.
4. The review **finds all three intentional defects**:
   - **(a) Placeholder:** Requirement 4 contains `TODO: Clarify how the retry
     backoff interval is calculated.` — must be reported as an open placeholder.
   - **(b) Inner contradiction:** Req. 3 demands up to 3 retries; Req. 6 demands
     an immediate stop on the first failure — both cannot be satisfied at the same
     time; must be reported as an internal contradiction.
   - **(c) Wrong path:** `tests/fixtures/plan-sample.md` does not exist under
     that name; the real file is `tests/fixtures/sample-plan.md` (basename
     swapped). The realism check reports `deviating` — file found, but path
     differs.
5. Fixable findings are applied directly to the document.
6. A **diff** against the snapshot is displayed.
7. Open design forks (e.g., the Retry-vs-Stop-on-Error contradiction) are
   presented to the user as a decision question.
8. Lock is removed; state `.claude/.preflight-reviewed` is written with the
   file hash.

---

## Scenario 2 — Plan Review

**Command:**
```
/preflight-plan tests/fixtures/sample-plan.md
```

**Expected behavior:**

1. The skill reads the `Spec:` line and loads `tests/fixtures/sample-spec-design.md`.
2. Lock is set.
3. Fact-check + 5 parallel `preflight:reviewer` stages (1–5) + consolidator.
4. The review **finds all four intentional defects**:
   - **(a) Missing coverage (Stage 1):** Push notifications from Spec Req. 5 are
     not covered by the plan — no task for Push/FCM/APNs.
   - **(b) Convention violation (Stage 2):** Task 4 hardcodes a 5-second interval
     (not configurable); filename `handler.go` does not follow the convention
     (concept-based name expected: `retry.go`).
   - **(c) Realism classification correct:** `internal/consumer/consumer_test.go`
     is declared as NEW/to-be-created and **must not** be flagged as `missing` —
     correct classification as `to-be-created`.
   - **(d) Security flaw (Stage 3):** Task 7 builds an SQL `UPDATE` statement via
     string concatenation from `req.body.pos` and `req.body.tenant`, enabling SQL
     injection. Must be reported as a security finding.
5. **Go/No-Go = No-Go** (missing Push coverage and SQL injection are both
   blockers).
6. Diff is displayed.
7. `.claude/.preflight-reviewed` contains the hash of `sample-plan.md` afterwards.

---

## Scenario 3 — No second nudge after known hash

**Prerequisite:** Scenario 2 completed; `.claude/.preflight-reviewed` contains
the hash of `sample-plan.md`.

**Step:** Call the plan command again without modifying the file:
```
/preflight-plan tests/fixtures/sample-plan.md
```

**Or:** Simulate a hook call by re-saving the same file (Write without changes).

**Expected behavior:**

- The hook produces **no nudge** because the file hash is already recorded in
  `.claude/.preflight-reviewed`.
- Claude receives no `additionalContext` and is not prompted to review again.
- Only when the file content changes (new hash) does the nudge reappear.

---

## Scenario 4 — Heuristic spec-lookup (no explicit reference)

**Command:**
```
/preflight-plan tests/fixtures/sample-plan-no-ref.md
```

**Expected behavior:**

1. The skill detects that no `Spec:` line is present in the plan.
2. It falls back to the date/topic heuristic: searches the fixtures directory
   (and/or `docs/superpowers/specs/`) for a spec file whose filename or heading
   matches the plan topic ("Notification Service").
3. The skill **reports which spec file was chosen** before proceeding (e.g.,
   "No explicit Spec: reference found — using `tests/fixtures/sample-spec-design.md`
   based on topic match.").
4. If exactly one candidate is found, the review proceeds with that spec.
5. If multiple candidates are found, the skill **asks the user** which spec to use
   before continuing.
6. The review then runs identically to Scenario 2 (same defects expected).
7. No crash or silent failure occurs in either the single-match or ambiguous case.

---

## Scenario 5 — CLI tool, no network surface

**Command:**
```
cp tests/fixtures/sample-spec-cli-design.md docs/superpowers/specs/
/preflight-spec docs/superpowers/specs/sample-spec-cli-design.md
```

**Expected behavior:**

1. The profiler asks about `network_surface` and the seven non-network facts it cannot derive.
2. `network_surface = none` settles `session_transport`, `renders_html` and `accepts_uploads`
   through the consistency conditions — none of the three is asked.
3. Ten of the twenty-four rules end up `not-applicable` without a question.
4. The written block keeps `SEC-SECRET-01`, `SEC-DEP-01` and `SEC-INJECT-01` as `required`.

---

## Scenario 6 — Web app with a cookie session

**Command:**
```
cp tests/fixtures/sample-spec-with-security-design.md docs/superpowers/specs/
# delete the block between the markers, then:
/preflight-spec docs/superpowers/specs/sample-spec-with-security-design.md
```

**Expected behavior:**

1. `SEC-CSRF-01` and `SEC-SESS-01` come back `required`.
2. The rewritten `facts` comment matches the one in the fixture.

---

## Scenario 7 — Bearer-token API

**Command:**
```
cp tests/fixtures/sample-spec-bearer-design.md docs/superpowers/specs/
/preflight-spec docs/superpowers/specs/sample-spec-bearer-design.md
/preflight-plan tests/fixtures/sample-plan-bearer.md
```

**Expected behavior:**

1. `SEC-CSRF-01` is `not-applicable` with a reason naming the transport.
2. `SEC-TOKEN-01` is `required`; `SEC-XSS-01` and `SEC-CSP-01` are `not-applicable`.
3. The plan review produces **no** CSRF finding — the `not-applicable` row is discarded by
   stage 6, not counted as `uncovered`.

This is the scenario that shows whether the rule really hangs on `session_transport` rather than
on the existence of forms.

---

## Scenario 8 — Drift

**Command:**
```
/preflight-plan tests/fixtures/sample-plan-upload.md
```

**Expected behavior:**

1. Stage 3 emits a `NEW-SURFACE` line naming `accepts_uploads`, `no -> yes` and a location.
2. `accepts_uploads = yes` would trigger `SEC-UPLOAD-01` (`required`, not in the block), so
   stage 6 grades it a **Blocker**.
3. The report points at `/preflight-profile --redo`.

---

## Scenario 9 — Agent dispatch

**Command:**
```
/preflight-spec <any spec>
```

**Expected behavior:**

1. `preflight:factchecker` appears as a dispatched subagent for the fact-check step.
2. `preflight:reviewer` appears as a dispatched subagent for the review step.
3. The report carries **no** fallback note. A report saying
   "Tiering inaktiv: `preflight:<name>` nicht auflösbar, Lauf auf `<fallback>`" means
   registration failed — a different failure from "no note, but also no dispatch". Both are bugs.

---

## Intentional defects (for the reviewer)

These defects are embedded in normal prose within the fixtures. The fixtures
themselves contain no meta-documentation about the defects so that the test
remains valid.

### `sample-spec-design.md`

| # | Defect | Expected detection |
|---|--------|--------------------|
| (a) | Requirement 4 contains `TODO: Clarify how the retry backoff interval is calculated.` — open placeholder, backoff unresolved. | Report as open placeholder / incomplete requirement. |
| (b) | Req. 3 demands up to 3 retries; Req. 6 demands an immediate stop on the first failure — both cannot be satisfied simultaneously. | Report as internal contradiction; ask the author for a decision. |
| (c) | Reference `tests/fixtures/plan-sample.md` — basename swapped; the real file is `tests/fixtures/sample-plan.md`. | Realism check reports `deviating` (file found, but path differs). |

### `sample-plan.md`

| # | Defect | Expected detection |
|---|--------|--------------------|
| (a) | Push notifications (Spec Req. 5) are not covered by the plan — no task for Push/FCM/APNs. | Report as missing coverage (Stage 1); Go/No-Go = No-Go. |
| (b) | Task 4 hardcodes a fixed 5-second interval (convention: must be configurable); filename `handler.go` instead of concept-based `retry.go`. | Report as convention violation (Stage 2). |
| (c) | Task 6 declares `internal/consumer/consumer_test.go` explicitly as NEW (does not exist in the repo). | Realism check classifies as `to-be-created` — must **not** be flagged as `missing`. |
| (d) | Task 7 builds the SQL `UPDATE` statement via string concatenation from `req.body.pos` / `req.body.tenant`. | Report as SQL injection / security flaw (Stage 3); Go/No-Go = No-Go. |

### `sample-plan-no-ref.md`

| # | Defect | Expected detection |
|---|--------|--------------------|
| — | No `Spec:` line present (intentional). | Skill must not crash; must fall back to date/topic heuristic, report which spec was chosen, and ask if ambiguous (Scenario 4). |

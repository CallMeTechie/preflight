# Security Profiler (main loop, not delegated)

Runs as step 4 of the skill, inside the lock, after the snapshot. Produces or
replaces the marked security block in the spec. Rules and facts come from
`security-matrix.md`; this file is the procedure.

## Phase 1 — Derive

Read the spec and settle each of the eleven facts: either back it with a
location in the document, or mark it `unbekannt`. **Never guess.** What cannot
be evidenced is unknown, and unknown is asked, not assumed.

## Phase 2 — Ask

Ask only for unknown facts, and filter adaptively: with `has_accounts = no`
every auth follow-up disappears; with `network_surface = none` the consistency
conditions already settle `session_transport`, `renders_html` and
`accepts_uploads`, so none of those are asked. Bundle the questions — up to four
in one round. Show the derived facts with their evidence at the same time so the
user can correct them.

Refresh the lock (`date +%s > <project>/.claude/.preflight-running`) after every
answer: this phase waits on a human and can outlast the 1800 s staleness
threshold.

## Phase 3 — Check and derive

First check the consistency conditions from `security-matrix.md`. A violation
sends you back to Phase 2 — except when the facts came from a stored comment
(the flagless mode and `--review`, which have no Phase 2): there, abort and
require `--redo`.

Then apply every rule row mechanically. No judgement at this step. If the spec already carries a
block, **carry every existing `not-applicable` status and its reason over** onto the matching ID
before showing the table. A re-derivation must never silently promote a ruled-out row back to
`required` — that would break the promise that a Bearer project stops seeing CSRF findings. An ID
that no longer appears at all drops out together with its reason.

## Phase 4 — Approve

Show the derived measures **before writing anything**. The user may set any row
to `not-applicable`. The reason is mandatory, is prefixed with the date of the
run (`(2026-08-26) interne Anwendung, kein Fernzugang`), and goes in the reason
column while the status column carries only `not-applicable`. Reject an empty or
merely affirming reason ("gilt nicht", "n/a") and ask again.

Rows may also move the other way: a `not-applicable` whose reason no longer holds goes back to the
status the matrix gives it, and the stored reason is dropped. Both directions are the user's call,
never the profiler's.

Refresh the lock after the approval, and again immediately before the write in
Phase 5.

## Phase 5 — Write

Source `plugin/lib/preflight-securitylib.sh`, call `preflight_security_block_state "<path>"` and act
on its exit code:

- `0` — replace the region between the markers, leave the rest of the spec alone
- `1` — append a fresh block at the end of the file
- `2` — **abort and report.** Never replace between damaged markers; it eats
  spec content.
- `3` — **abort and report the path.** The file does not exist or cannot be read. This is not a
  marker problem: say "Spec nicht gefunden: `<path>`", never "beschädigte Marker". Reporting it as
  damage sends the user looking for a corruption that is not there.

Block format:

    <!-- preflight:security:begin -->
    <!-- facts: network_surface=... has_accounts=... auth_method=...
         has_privilege_levels=... session_transport=... has_owned_data=...
         is_multi_tenant=... persistence=... renders_html=... accepts_uploads=...
         handles_pii=... -->

    ## Security Requirements

    | ID | Maßnahme | Geltungsbereich | Status | Begründung |
    |----|----------|-----------------|--------|------------|
    | SEC-CSRF-01 | Anti-CSRF-Token | alle zustandsändernden Routen | required | Cookie-Session |
    <!-- preflight:security:end -->

The `facts` comment may wrap. Binding: `<!-- facts:` opens, ` -->` closes,
between them nothing but `key=value` pairs separated by whitespace, and no pair
is split across lines. The wrap is deliberate — it keeps a git diff pointing at
the single fact that changed.

## Reading an existing block

Before deriving from stored facts, call `preflight_security_facts_valid "<path>"`. It reads only the
comment **between the markers** — a spec may quote the format in its prose, and the first
`<!-- facts:` in the file would then be an example, not the state. Exit `1` means abort and require `--redo`: an unknown key, a value
outside its allowed set, a missing fact, or a violated consistency condition.
Nothing is completed, rounded or defaulted — a silently filled-in fact deletes a
`required` row and no test notices.

A block whose `facts` comment is gone entirely is the same case: there is
nothing to derive from, and the facts are never reconstructed from the table.

## Edge case: no network surface

With `network_surface = none` (CLI tool, library, Claude plugin) the consistency
conditions settle three further facts, and ten of the twenty-four rules fall to
`not-applicable` without a question. The seven non-network facts still apply:
`has_accounts`, `auth_method`, `has_privilege_levels`, `has_owned_data`,
`is_multi_tenant`, `persistence`, `handles_pii`. `SEC-INJECT-01` stays `required` regardless — its
trigger is `immer`, because "do not trust the input" is not the same claim as "has a network
surface". A CLI tool with a local SQLite store additionally keeps `SEC-SQLI-01`, and that is
correct.

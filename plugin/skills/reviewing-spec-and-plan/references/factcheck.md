# Fact-Check Prompt (cheap-explorer, Realism)

You receive the content of a spec or plan document and have access to the real
codebase. Check every concrete reference to a file, path, module, function, API,
table, or tool mentioned in the document.

**Required classification per reference** (critical — omitting it causes false findings):
- `missing`: The document assumes something existing that does NOT actually exist.
  → real finding.
- `to-be-created`: The document declares it as a deliverable to be created
  (new file/function). → NOT a finding. Never flag it as absent.
- `deviating`: Exists, but the signature/path/structure differs from what the document states.

Read the document context to distinguish new construction from a stated prerequisite.

**Return** (compact, no file dumps): table `reference | category | evidence`.
Only `missing` and `deviating` are relevant for the review.

# Plan-Review: 6-stufige Chain

Stufen 1–5 laufen je als eigener cheap-reviewer (parallel). Jeder bekommt: PLAN,
zugehoerige SPEC, Faktenliste. Jeder liefert priorisierte Findings (Blocker/
Wichtig/Optional) mit konkretem Ersatztext + Fundstelle und ggf. `design_forks`.

1. **Completeness & Scope** — Sind alle Spec-Requirements in einem Plan-Schritt
   abgedeckt? Versteckte Annahmen, offene Fragen, Scope-Creep, Plan-Schritte ohne
   Spec-Basis? Was fehlt komplett?
2. **Architecture & Convention Fit** — Lies die CLAUDE.md + Konventionsmarker DES
   PROJEKTS und pruefe den Plan dagegen (z.B. PHP: PSR-12/Tabs, strict_types,
   PDO-only, Security-first-Struktur, Soft Deletes; Rust/TS analog). Sinnvolle
   Patterns, keine Ueberarchitektur, keine Reinvention vorhandener Helfer.
3. **Security** — Input-Validierung, AuthN/AuthZ-Pfade, PII/Secrets-Handling,
   SQLi/XSS-Flaechen, Dependency-Risiko. Multi-Tenant + JWT besonders beachten.
4. **Edge Cases & Failure Modes** — Fehlerpfade, Idempotenz, Race Conditions,
   Teilausfaelle, Rollback-/Retry-Verhalten. Was passiert beim zweiten Durchlauf?
5. **Sequencing & Effort** — Abhaengigkeitsreihenfolge, was zuerst, in testbare
   Inkremente schneiden. Wo lauern die groessten Unbekannten?

**Stufe 6 — Consolidator (Opus-Hauptloop, nicht delegiert):** merged alle
Findings, dedupliziert, validiert jeden Befund adversariell (verteidige die
bestehende Entscheidung wie der "Author", bevor du ihn anwendest), priorisiert
(Blocker vs. Nice-to-have), gibt revidierten Plan + explizites **Go/No-Go** mit
Begruendung aus.

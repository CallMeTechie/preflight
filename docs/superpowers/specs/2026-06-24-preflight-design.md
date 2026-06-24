# Design: preflight

- **Datum:** 2026-06-24
- **Status:** Entwurf zur Review
- **Autor:** Marc Backes (CallMeTechie) / Claude

## Problem

Der superpowers-Workflow läuft `brainstorming → writing-plans → Umsetzung`. Dabei
entstehen Spec-Dokumente (`docs/superpowers/specs/YYYY-MM-DD-<topic>-design.md`)
und Plan-Dokumente (`docs/superpowers/plans/YYYY-MM-DD-<feature>.md`).

Beide Skills haben heute nur schwache Eigen-Checks:

- `brainstorming` macht einen inline *Spec self-review* (Platzhalter/Widersprüche)
  plus ein User-Review-Gate.
- `writing-plans` macht nur einen agent-internen Self-Review und **kein** externes
  Gate, bevor die Umsetzung startet.

Es fehlt ein **stärkerer, automatisierter Review** ("preflight"-Check vor dem
Abheben), der über diese Selbst-Checks hinausgeht: kritisch (adversarial),
vollständigkeitsprüfend, Spec↔Plan-konsistenzprüfend und realismusprüfend gegen
die echte Codebase — und der gefundene Mängel **direkt behebt**, statt sie nur
aufzulisten.

## Ziele

1. Nach dem Schreiben einer Spec **und** nach dem Schreiben eines Plans läuft
   automatisch ein Review.
2. Der Review prüft vier Dimensionen: Adversarial/Kritik, Qualität/Vollständigkeit,
   Spec↔Plan-Konsistenz, Umsetzbarkeit/Realismus.
3. Der Review **behebt alle behebbaren Mängel direkt** im Dokument. Nur echte
   Design-Gabelungen (ohne objektiv richtige Antwort) werden dem Nutzer als
   Entscheidungsliste vorgelegt.
4. Der Trigger ist automatisch (Hook nudged), aber nicht blockierend; der Review
   bleibt zusätzlich manuell per Slash-Command aufrufbar.
5. Der Review läuft regelkonform zur Tiering-Regel: Reviewer-Arbeit im
   `cheap-reviewer`, Codebase-Faktencheck im `cheap-explorer`, Opus nur für
   Synthese/Urteil/Fixes (Consolidator-Rolle).

## Nicht-Ziele

- Kein Code-Review von Implementierungs-Diffs (dafür existiert `review.md`).
- Kein hartes Blockieren des Workflows (der Hook nudged nur).
- Keine Änderung der superpowers-Skills im Plugin-Cache (würde bei Updates
  überschrieben). Stattdessen eigenständiges, additives Plugin.

## Überblick

Ein eigenständiges Plugin `preflight` (Struktur analog zu fleet-manager). Es
bündelt drei Bausteine mit klarer Rollentrennung:

| Baustein | Rolle | Kann selbst Reasoning? |
|---|---|---|
| **Hook** | Trigger: erkennt geschriebene Spec/Plan-Datei, stößt Skill an | nein (deterministisches Shell) |
| **Skill** | Gehirn: orchestriert Review, wendet Fixes an | ja (Opus-Hauptloop) |
| **Commands** | manueller Einstieg `/preflight-spec`, `/preflight-plan` | ja (rufen Skill) |

**Zwei Review-Mechanismen, je nach Dokumenttyp:**

- **Spec** → Author↔Reviewer-Dialog (Format aus `review.md`).
- **Plan** → 6-stufige Review-Chain (5 parallele Reviewer + Consolidator).

Datenfluss:

```
Write(spec/plan-Datei)
   └─► PostToolUse-Hook (detect-spec-plan-write.sh)
         ├─ Pfad matcht specs/  → Modus "spec"
         ├─ Pfad matcht plans/  → Modus "plan"
         └─ Hash unbekannt?     → additionalContext-Reminder ("invoke preflight-Skill, Modus=X, Pfad=Y")
                                    │
   Opus-Hauptloop ◄───────────────┘
         └─► Skill reviewing-spec-and-plan
               ├─ cheap-explorer: Codebase-Faktencheck (Realismus)
               ├─ Spec: cheap-reviewer Author↔Reviewer-Dialog
               │   ODER
               │   Plan: cheap-reviewer ×5 (Chain-Stufen 1–5, parallel)
               ├─ Opus (Consolidator): Synthese → Fixes anwenden (ggf. via cheap-coder)
               ├─ adaptive Re-Review (voll vs. fokussiert)
               ├─ Design-Gabelungen dem Nutzer vorlegen
               └─ State-Datei mit finalem Hash aktualisieren
```

## Verzeichnisstruktur

```
preflight/
└── plugin/
    ├── .claude-plugin/
    │   └── plugin.json
    ├── skills/
    │   └── reviewing-spec-and-plan/
    │       └── SKILL.md
    ├── commands/
    │   ├── preflight-spec.md
    │   └── preflight-plan.md
    ├── hooks/
    │   ├── hooks.json
    │   └── detect-spec-plan-write.sh
    └── CLAUDE.md
```

## Baustein 1: Hook (Trigger)

**Event:** `PostToolUse`, Matcher `Write|Edit`.

**Skript `detect-spec-plan-write.sh`:**

1. Liest das Tool-Input-JSON von stdin, extrahiert `tool_input.file_path`.
2. Matcht den Pfad:
   - `**/docs/superpowers/specs/*-design.md` → Modus `spec`
   - `**/docs/superpowers/plans/*.md` → Modus `plan`
   - sonst: exit 0 (nichts tun).
3. **Debounce:** Berechnet den SHA-256 des Datei-Inhalts. Schlägt in der
   State-Datei `<project>/.claude/.preflight-reviewed` nach (Format: eine Zeile
   pro Pfad, `<sha>\t<pfad>`). Ist der aktuelle Hash dort bereits als reviewt
   vermerkt → exit 0 (kein erneuter Nudge).
4. Andernfalls gibt der Hook `additionalContext` aus (PostToolUse-JSON-Output),
   der den Hauptloop anweist: *„Eine <Modus>-Datei wurde nach <Pfad> geschrieben.
   Bevor du fortfährst, invoke die Skill `reviewing-spec-and-plan` mit Modus=<Modus>
   und Pfad=<Pfad>."*

**Wichtig:** Der Hook schreibt **nicht** selbst in die State-Datei — das macht der
Skill nach erfolgreichem Review (mit dem Post-Fix-Hash). So lösen die Fixes des
Reviews keinen neuen Nudge aus; eine spätere echte Überarbeitung durch den Nutzer
(neuer Hash) dagegen schon.

**Nicht blockierend:** Der Hook gibt nie einen Block-Exit-Code zurück.

## Baustein 2: Skill (Gehirn) — `reviewing-spec-and-plan`

**Eingang:** Modus (`spec` | `plan`) + Dateipfad. Quelle: entweder der
Hook-Reminder oder ein Slash-Command-Argument.

### Schritt 1 — Kontext laden
- **Spec-Modus:** liest die Spec-Datei.
- **Plan-Modus:** liest den Plan **und** die zugehörige Spec. Zuordnung:
  1. **Verweis bevorzugt:** existiert im Plan eine Zeile `Spec: <pfad>`, gilt der.
  2. **Sonst Heuristik:** gleiches Datum/Topic im Dateinamen; bei Mehrdeutigkeit
     fragt der Skill den Nutzer.

### Schritt 2 — Codebase-Faktencheck (cheap-explorer, Haiku)
Sammelt für die Realismus-Dimension Fakten gegen die echte Codebase: existieren
referenzierte Pfade, Dateien, APIs, Funktionen? Stimmen die Annahmen über die
vorhandene Struktur? Gibt eine kompakte Faktenliste zurück (existiert / existiert
nicht / abweichend), die den Reviewern als Grundlage dient.

### Schritt 3a — Spec-Review: Author↔Reviewer-Dialog (cheap-reviewer, Sonnet)
Der Subagent simuliert den Dialog (Format aus `review.md`):

- **Author:** verteidigt Entscheidungen, erklärt Tradeoffs, schlägt beim
  Nachgeben konkrete Fixes vor.
- **Reviewer:** Senior, bringt **pro Runde mindestens einen substanziellen
  Einwand**, liefert konkreten Ersatztext (nicht nur Beschreibung).
- Runden-Label `### Round N — [Topic]`. Der Author muss **mindestens einmal pro
  Runde verteidigen** statt sofort einzuknicken. Early Termination:
  „✅ Consensus reached after N rounds." Default max. 5 Runden (per Argument
  überschreibbar).

**Topic-Priorität — Spec** (Scope = Spec-Datei + Faktenliste):
1. Vollständigkeit — Platzhalter, TBD, undefinierte Anforderungen, fehlende
   Erfolgskriterien
2. Klarheit/Ambiguität — zweideutig interpretierbare Anforderungen, vage Begriffe
3. Interne Konsistenz — Abschnitte widersprechen sich; Architektur ≠
   Feature-Beschreibungen
4. Scope & YAGNI — zu groß für einen Plan? unnötige Features? Decomposition nötig?
5. Realismus — Annahmen über Codebase/Technik, die laut Faktenliste nicht halten
6. Risiken/Blind Spots (adversarial) — Failure-Modes, optimistische Abkürzungen,
   unbehandelte Edge Cases

### Schritt 3b — Plan-Review: 6-stufige Review-Chain
Die Stufen 1–5 laufen **parallel** als je ein `cheap-reviewer`-Subagent
(unabhängige Dimensionen; jeder bekommt Plan + Quell-Spec + Faktenliste). Jeder
Reviewer liefert priorisierte Findings mit konkretem Ersatztext. Stufe 6 ist der
**Consolidator (Opus-Hauptloop)**.

1. **Completeness & Scope** — Sind alle Requirements abgedeckt? Versteckte
   Annahmen, offene Fragen, Scope-Creep? Was fehlt komplett? (deckt auch
   Spec↔Plan-Abdeckung/Drift ab)
2. **Architecture & Convention Fit** — Passt der Plan zu den Konventionen *des
   jeweiligen Projekts*? Der Reviewer liest die **CLAUDE.md + Konventionsmarker
   des Projekts** und prüft dagegen. Für PHP-Projekte z.B. PSR-12/Tabs,
   `strict_types`, PDO-only, Security-first-Verzeichnisstruktur, Soft Deletes;
   für Rust/TS entsprechend deren Konventionen. Sinnvolle Patterns, keine
   Überarchitektur, keine Reinvention vorhandener Helfer.
3. **Security** — Input-Validierung, AuthN/AuthZ-Pfade, PII/Secrets-Handling,
   SQLi/XSS-Flächen, Dependency-Risiko. Besonders relevant bei Multi-Tenant + JWT.
4. **Edge Cases & Failure Modes** — Fehlerpfade, Idempotenz, Race Conditions,
   Teilausfälle, Rollback-/Retry-Verhalten. Was passiert beim zweiten Durchlauf?
5. **Sequencing & Effort** — Abhängigkeitsreihenfolge, was zuerst, in testbare
   Inkremente schneiden. Wo lauern die größten Unbekannten?
6. **Consolidator (Opus)** — merged alle Findings, dedupliziert, priorisiert
   (Blocker vs. Nice-to-have), gibt **revidierten Plan + Go/No-Go** aus. Siehe
   Schritt 4.

### Schritt 4 — Consolidation, Synthese & Fix-Anwendung (Opus-Hauptloop)
Diese Stufe ist für Spec- *und* Plan-Modus der Abschluss (im Plan-Modus = Chain-
Stufe 6):

- Opus merged/dedupliziert die Findings und validiert jeden Befund **adversariell**
  (spielt den „Author" aus `review.md`: verteidigt die bestehende Entscheidung,
  prüft Tradeoffs), bevor er angewendet wird — damit kein schwacher Einwand blind
  übernommen wird.
- **Alle behebbaren Befunde werden direkt im Dokument angewendet** — bei
  umfangreichen mechanischen Edits via `cheap-coder`, sonst direkt.
- **Design-Gabelungen** (Befunde, deren Behebung eine echte Designentscheidung
  ohne objektiv richtige Antwort verlangt) werden *nicht* geraten, sondern dem
  Nutzer als kurze Entscheidungsliste vorgelegt (eine Frage je Gabelung).
- Im Plan-Modus zusätzlich ein explizites **Go/No-Go** mit Begründung.

### Schritt 5 — Adaptive Re-Review
Nach dem Anwenden der Fixes wägt der Hauptloop ab, **ob und in welcher Tiefe**
erneut geprüft wird:
- **Fokussierte Runde** (nur die geänderten Abschnitte/Dimensionen), wenn die
  Fixes lokal und isoliert waren.
- **Volle Runde** (Dialog bzw. komplette Chain), wenn die Fixes strukturell/breit
  waren (z.B. Scope-Schnitt, Architekturänderung, viele Querbezüge).
- **Kein zweiter Durchgang**, wenn nur triviale Korrekturen (Platzhalter,
  Tippfehler) angewendet wurden.
Die Entscheidung wird dem Nutzer mit einer Ein-Satz-Begründung mitgeteilt.

### Schritt 6 — State aktualisieren & berichten
- Schreibt den finalen Datei-Hash in `.claude/.preflight-reviewed`.
- Gibt dem Nutzer ein kompaktes Urteil: Summary-Tabelle (Topic/Stufe, Runden,
  Action Items), Liste der angewendeten Fixes, offene Design-Gabelungen,
  Re-Review-Entscheidung und (Plan) das Go/No-Go.

## Baustein 3: Commands (manueller Einstieg)

- `/preflight-spec [pfad] [max-rounds]` — invoke Skill im Spec-Modus. Ohne Pfad:
  jüngste Datei in `docs/superpowers/specs/`.
- `/preflight-plan [pfad] [max-rounds]` — invoke Skill im Plan-Modus. Ohne Pfad:
  jüngste Datei in `docs/superpowers/plans/`.

Beide sind dünne Wrapper, die nur den Skill mit den richtigen Argumenten aufrufen.

## Subagent-Tiering (gemäß ~/.claude/CLAUDE.md)

| Arbeit | Agent | Modell |
|---|---|---|
| Codebase-Faktencheck (Realismus) | `cheap-explorer` | Haiku |
| Spec-Dialog / Plan-Chain-Stufen 1–5 | `cheap-reviewer` | Sonnet |
| umfangreiche mechanische Fix-Edits | `cheap-coder` | Sonnet |
| Consolidation, Urteil, Fix-Entscheidung, Go/No-Go, Design-Gabelungen | Opus-Hauptloop | Opus |

## Fehlerbehandlung & Edge Cases

- **Leere/sehr kurze Datei:** Skill meldet „zu wenig Inhalt für Review" und bricht
  ab (kein Pseudo-Review).
- **Plan ohne auffindbare Spec:** Skill fragt den Nutzer nach der Spec; ohne Spec
  läuft der Plan-Review ohne die Konsistenz-Dimension (Stufe 1 mit Hinweis).
- **State-Datei fehlt/korrupt:** wird neu angelegt; im Zweifel wird gereviewt
  (fail-open, lieber ein Review zu viel).
- **Hook ohne Hashing-Tool:** Skript nutzt nur POSIX-Tools + `shasum`/`sha256sum`;
  fehlt das Tool, nudged der Hook ohne Debounce (fail-open).
- **Nudge-Schleife:** durch Hash-Debounce + State-Update nach Fix ausgeschlossen.

## Testing

- **Hook-Skript:** Unit-Tests mit gefälschten Tool-Input-JSONs (Spec-Pfad,
  Plan-Pfad, Fremd-Pfad, bereits-reviewter Hash) → korrekter Modus / kein Nudge.
- **State-Debounce:** Hash bekannt vs. unbekannt → Nudge ja/nein.
- **Skill Spec (Integration):** echte Beispiel-Spec mit eingebauten Mängeln
  (Platzhalter, Widerspruch, falscher Pfad) → Review findet + fixt sie.
- **Skill Plan (Integration):** echter Plan mit fehlender Spec-Abdeckung +
  Konventionsverstoß + Security-Lücke → Chain-Stufen 1/2/3 erkennen je ihren
  Befund, Consolidator merged + gibt No-Go.
- **Modus-Zuordnung Plan→Spec:** Verweis bevorzugt, Heuristik als Fallback.

## Offene Punkte

Keine — Entscheidungen sind getroffen (Name `preflight`; zwei Gates; Hook nudged
nicht-blockierend; Spec=Dialog, Plan=6-stufige Chain; Plan↔Spec=Verweis-bevorzugt-
sonst-Heuristik; alle Fixes anwenden; adversarielle Consolidation; adaptive
Re-Review; manuelle Commands `/preflight-spec` + `/preflight-plan`).

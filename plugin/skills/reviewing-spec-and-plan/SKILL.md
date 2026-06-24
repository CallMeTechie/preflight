---
name: reviewing-spec-and-plan
description: Use to run a deep preflight review of a superpowers spec or plan document — adversarial Author/Reviewer dialogue for specs, a 6-stage review chain for plans — then apply all fixable findings with a snapshot+diff. Invoked by the preflight PostToolUse hook (advisory) or the /preflight-spec and /preflight-plan commands.
---

# Reviewing Spec and Plan (preflight)

**Eingang:** `Modus` (`spec` | `plan`) + `Pfad` zur Datei. Quelle: Hook-Reminder
oder Command-Argument. Referenz-Prompts liegen unter `references/` neben dieser Datei.

**Tiering (verbindlich):** Reviewer-Arbeit an `cheap-reviewer`, Codebase-Faktencheck
an `cheap-explorer`, umfangreiche mechanische Fix-Edits an `cheap-coder`; der
Hauptloop macht nur Consolidation/Urteil/Fix-Entscheidung.

## Schritt 1 — Kontext laden
- Lies die Datei unter `Pfad`. Ist sie leer oder < ~15 Zeilen substanziell:
  melde "zu wenig Inhalt fuer Review" und brich ab.
- **Plan-Modus:** finde die zugehoerige Spec. (1) Gibt es im Plan eine Zeile
  `Spec: <pfad>`, gilt der. (2) Sonst Heuristik ueber gleiches Datum/Topic im
  Dateinamen unter `docs/superpowers/specs/`; bei Mehrdeutigkeit frage den Nutzer.
  Findest du keine Spec, laeuft der Review ohne die Konsistenz-Dimension (sag es).

## Schritt 2 — Lock setzen
Lege `<project>/.claude/.preflight-running` mit aktuellem Unix-Timestamp an
(`date +%s`). Reihenfolge ist kritisch: **Lock zuerst**, dann editieren, am Ende
Lock entfernen, dann State schreiben (Schritt 7). Der Lock unterdrueckt die
review-eigenen Edits am Dokument im Hook.

## Schritt 3 — Faktencheck
Dispatch einen `cheap-explorer` mit dem Prompt aus `references/factcheck.md` plus
dem Dokumentinhalt. Nimm nur Befunde `fehlt-faelschlich`/`abweichend` in den Review.

## Schritt 4 — Review
- **Spec-Modus:** Dispatch EINEN `cheap-reviewer` mit `references/spec-dialogue.md`
  (Dokument + Faktenliste + Max-Runden).
- **Plan-Modus:** Dispatch FUENF `cheap-reviewer` PARALLEL, je ein Mandat aus
  `references/plan-chain.md` (Stufen 1–5), jeweils mit Plan + Spec + Faktenliste;
  Stufe 6 (Consolidator) ist Schritt 5.

## Schritt 5 — Consolidation, Snapshot, Fixes, Diff (Hauptloop) (= Stufe 6 der Plan-Chain: Consolidator)
1. Merge/dedupliziere die Findings; validiere jeden Befund adversariell, bevor du
   ihn anwendest (kein schwacher Einwand wird blind uebernommen).
2. **Snapshot vor dem ersten Fix:** ist die Datei in einem Git-Repo und uncommittet,
   committe sie; sonst kopiere nach `<datei>.preflight.bak`.
3. Wende ALLE behebbaren Befunde direkt am Dokument an (grosse mechanische Edits via
   `cheap-coder`). Echte `design_forks` NICHT raten — sammle sie fuer Schritt 7.
4. Zeige dem Nutzer den **Diff** gegen den Snapshot (nicht nur eine Fix-Liste).
5. **Plan-Modus:** formuliere ein explizites **Go/No-Go** mit Begruendung.

## Schritt 6 — Adaptive Re-Review
Waege ab, ob erneut geprueft wird — und teile die Entscheidung mit Ein-Satz-
Begruendung mit:
- **Fokussierte Runde** (nur geaenderte Abschnitte/Dimensionen) bei lokalen Fixes.
- **Volle Runde** (Dialog bzw. komplette Chain) bei strukturellen/breiten Aenderungen.
- **Kein zweiter Durchgang** bei nur trivialen Korrekturen.
Bei einer Re-Review bleibt der Lock aktiv und es gilt erneut Schritt 4–5.

## Schritt 7 — Lock loesen, State, Bericht
- Entferne `.preflight-running`, **dann** schreibe `<hash>\t<pfad>` (finaler
  SHA-256 der Datei) nach `.claude/.preflight-reviewed` (vorhandene Zeile fuer den
  Pfad ersetzen).
- Lege offene `design_forks` dem Nutzer als kurze Entscheidungsliste vor (eine
  Frage je Gabelung).
- Berichte kompakt: Summary-Tabelle, Diff-Hinweis, offene Gabelungen, Re-Review-
  Entscheidung und (Plan) das Go/No-Go.

## Fehlerpfade
- Brichst du vorzeitig ab, entferne den Lock trotzdem (sonst schweigt der Hook bis
  zur 30-min-Staleness).
- Fehlt `.claude/`, lege es an.

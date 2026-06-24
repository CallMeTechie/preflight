# Manuelle Integrations-Tests — preflight Plugin

Diese Anleitung verifiziert den Skill-Pfad end-to-end gegen die Demo-Fixtures.
Das Skill-Verhalten ist LLM-getrieben und nicht automatisiert testbar; dies ist
die ehrliche Test-Grenze.

**Voraussetzung:** Das Plugin ist in Claude Code registriert
(`~/.claude/plugins/preflight` oder via `plugin add`).
Die Fixtures liegen unter `tests/fixtures/` und das Verzeichnis liegt bewusst
**nicht** unter `docs/superpowers/` — der Hook triggert beim Schreiben dieser
Fixtures deshalb nicht.

---

## Szenario 1 — Spec-Review

**Command:**
```
/preflight-spec tests/fixtures/sample-spec-design.md
```

**Erwartetes Verhalten:**

1. Die Skill setzt den Lock `.claude/.preflight-running`.
2. Ein `cheap-explorer` prüft Datei-Referenzen auf Existenz.
3. Ein `cheap-reviewer` führt den Author/Reviewer-Dialog.
4. Die Review **findet alle drei absichtlichen Mängel**:
   - **(a) Platzhalter:** Anforderung 4 enthält `TODO: Klären wie das
     Retry-Backoff-Intervall berechnet wird.` — muss als offener Platzhalter
     gemeldet werden.
   - **(b) Innerer Widerspruch:** Anf. 3 fordert bis zu 3 Retries, Anf. 6
     fordert sofortigen Stopp bei erstem Fehler — beides gleichzeitig ist nicht
     erfüllbar; muss als Widerspruch gemeldet werden.
   - **(c) Falscher Pfad:** `tests/fixtures/plan-sample.md` existiert nicht unter
     diesem Namen; die real existierende Datei heisst `tests/fixtures/sample-plan.md`
     (Basename vertauscht). Der Realismus-Check meldet `abweichend` — Datei gefunden,
     aber Pfad weicht ab.
5. Behebbare Findings werden direkt am Dokument angewendet.
6. Ein **Diff** gegen den Snapshot wird angezeigt.
7. Offene Design-Gabelungen (z. B. Widerspruch Retry vs. Stop-on-Error) werden
   dem Nutzer als Entscheidungsfrage vorgelegt.
8. Lock wird entfernt, State `.claude/.preflight-reviewed` wird mit dem Hash der
   Datei beschrieben.

---

## Szenario 2 — Plan-Review

**Command:**
```
/preflight-plan tests/fixtures/sample-plan.md
```

**Erwartetes Verhalten:**

1. Die Skill liest die `Spec:`-Zeile und lädt `tests/fixtures/sample-spec-design.md`.
2. Lock wird gesetzt.
3. Faktencheck + 5 parallele `cheap-reviewer` (Stufen 1–5) + Consolidator.
4. Die Review **findet alle drei absichtlichen Mängel**:
   - **(a) Fehlende Abdeckung (Stufe 1):** Push-Benachrichtigungen aus Spec Anf. 5
     sind im Plan nicht abgedeckt — kein Task für Push/FCM/APNs.
   - **(b) Konventionsverstoß (Stufe 2):** Task 4 hardcodet ein 5-Sekunden-Intervall
     (nicht konfigurierbar); Dateiname `handler.go` folgt nicht der Konvention
     (Konzept-basierter Name erwartet: `retry.go`).
   - **(c) Realismus-Klassifizierung korrekt:** `internal/consumer/consumer_test.go`
     wird als NEU/zu-erstellen deklariert und **darf nicht** als „Datei fehlt"
     gerügt werden — korrekte Klassifizierung als `new/to-create`.
5. **Go/No-Go = No-Go** (fehlende Push-Abdeckung ist ein Blocker).
6. Diff wird angezeigt.
7. `.claude/.preflight-reviewed` enthält danach den Hash von `sample-plan.md`.

---

## Szenario 3 — Kein zweiter Nudge nach bekanntem Hash

**Voraussetzung:** Szenario 2 wurde abgeschlossen; `.claude/.preflight-reviewed`
enthält den Hash von `sample-plan.md`.

**Schritt:** Rufe den Plan-Command erneut auf, ohne die Datei zu verändern:
```
/preflight-plan tests/fixtures/sample-plan.md
```

**Oder:** Simuliere einen Hook-Aufruf durch erneutes Speichern derselben Datei
(Write ohne Änderung).

**Erwartetes Verhalten:**

- Der Hook gibt **keinen Nudge** aus, weil der Hash der Datei bereits in
  `.claude/.preflight-reviewed` eingetragen ist.
- Claude erhält keinen `additionalContext` und wird nicht erneut zur Review
  aufgefordert.
- Erst wenn der Inhalt der Datei geändert wird (neuer Hash), erscheint
  der Nudge wieder.

---

## Absichtlich eingebaute Mängel (für den Prüfer)

Diese Mängel sind im normalen Fliesstext der Fixtures versteckt. Die Fixtures
selbst enthalten keine Meta-Doku über die Mängel, damit der Test valide bleibt.

### `sample-spec-design.md`

| # | Mangel | Erwartete Erkennung |
|---|--------|---------------------|
| (a) | Anforderung 4 enthält `TODO: Klären wie das Retry-Backoff-Intervall berechnet wird.` — offener Platzhalter, Backoff ungeklärt. | Als offener Platzhalter/unvollständige Anforderung melden. |
| (b) | Anf. 3 fordert bis zu 3 Retries; Anf. 6 fordert sofortigen Stopp bei erstem Fehler — beides gleichzeitig ist nicht erfüllbar. | Als inneren Widerspruch melden; Entscheidungsfrage an den Autor. |
| (c) | Referenz `tests/fixtures/plan-sample.md` — Basename vertauscht; die reale Datei heisst `tests/fixtures/sample-plan.md`. | Realismus-Check meldet `abweichend` (Datei gefunden, aber Pfad weicht ab). |

### `sample-plan.md`

| # | Mangel | Erwartete Erkennung |
|---|--------|---------------------|
| (a) | Push-Benachrichtigungen (Spec Anf. 5) sind im Plan nicht abgedeckt — kein Task für Push/FCM/APNs. | Als fehlende Abdeckung melden (Stufe 1); Go/No-Go = No-Go. |
| (b) | Task 4 hardcodet ein festes 5-Sekunden-Intervall (Konvention: konfigurierbar); Dateiname `handler.go` statt konzeptbasiertem `retry.go`. | Als Konventionsverstoß melden (Stufe 2). |
| (c) | Task 6 deklariert `internal/consumer/consumer_test.go` explizit als NEU (existiert nicht im Repo). | Realismus-Check klassifiziert als `new/to-create` — darf **nicht** als „Datei fehlt" gerügt werden. |

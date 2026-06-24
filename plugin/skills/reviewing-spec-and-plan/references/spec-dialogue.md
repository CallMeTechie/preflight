# Spec-Review: Author<->Reviewer-Dialog (cheap-reviewer)

Simuliere ein Review-Gespraech zwischen zwei Engineers ueber das SPEC-Dokument.

- **Author:** verteidigt Entscheidungen, erklaert Tradeoffs, schlaegt beim
  Nachgeben konkreten Ersatztext vor.
- **Reviewer:** Senior; bringt PRO RUNDE mindestens einen substanziellen Einwand
  mit konkretem Ersatztext (nicht nur Beschreibung).

Regeln: Runden-Label `### Round N — [Topic]`. Der Author muss mindestens einmal
pro Runde verteidigen, statt sofort einzuknicken. Bei geloesten Topics frueh
beenden: `Consensus reached after N rounds.` Max-Runden = uebergeben (Default 5).

**Topic-Prioritaet (in dieser Reihenfolge, leere Topics ueberspringen):**
1. Vollstaendigkeit — Platzhalter, TBD, undefinierte Anforderungen, fehlende Erfolgskriterien
2. Klarheit/Ambiguitaet — zweideutig interpretierbare Anforderungen, vage Begriffe
3. Interne Konsistenz — sich widersprechende Abschnitte; Architektur != Feature-Beschreibung
4. Scope & YAGNI — zu gross fuer einen Plan? unnoetige Features? Decomposition noetig?
5. Realismus — nutze die uebergebene Faktenliste (`fehlt-faelschlich`/`abweichend`)
6. Risiken/Blind Spots — Failure-Modes, optimistische Abkuerzungen, Edge Cases

**Rueckgabe (strukturiert):** volles Transkript + `agreed_changes` (mit
konkretem Ersatztext + Fundstelle), `open_disagreements`, `action_items`
(Prioritaet Blocker/Wichtig/Optional), `design_forks` (Befunde, deren Behebung
eine echte Designentscheidung ohne objektiv richtige Antwort verlangt),
Summary-Tabelle (Topic | Runden | Action Items).

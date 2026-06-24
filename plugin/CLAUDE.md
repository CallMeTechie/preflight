# preflight Plugin

Advisory nudge + review skill for superpowers spec and plan documents.

## Drei Bausteine

### 1. Hook — `plugin/hooks/detect-spec-plan-write.sh`

PostToolUse-Hook. Wird nach jedem `Write`-Aufruf gefeuert.
- Erkennt Spec-Dateien (`docs/superpowers/specs/*-design.md`) und Plan-Dateien
  (`docs/superpowers/plans/*.md`) am Pfad.
- **Blockiert nie.** Gibt im Trefferfall `hookSpecificOutput.additionalContext`
  aus — ein Text-Nudge, der Claude auffordert, die Skill zu invoken.
- Unterdrückt den Nudge wenn: (a) die Datei bereits unter ihrem aktuellen Hash
  reviewed wurde (State-Datei), oder (b) gerade ein Review läuft (Lock-Datei).

### 2. Skill — `plugin/skills/reviewing-spec-and-plan/`

Kernlogik. Wird vom Hook-Nudge **oder** direkt durch einen Command ausgelöst.

**Spec-Modus:** adversarialer Author/Reviewer-Dialog (bis `max-rounds`).
**Plan-Modus:** 6-stufige Review-Chain (Stufen 1–5 parallel, Stufe 6 = Consolidator).

Ablauf: Lock setzen → Faktencheck (`cheap-explorer`) → Review (`cheap-reviewer`)
→ Findings konsolidieren → Snapshot + Fixes + Diff → adaptive Re-Review →
Lock lösen → State schreiben → Bericht + offene Design-Gabelungen.

### 3. Commands — `plugin/commands/`

| Command              | Beschreibung                                |
|----------------------|---------------------------------------------|
| `/preflight-spec`    | Startet Skill im Spec-Modus für `[path]`    |
| `/preflight-plan`    | Startet Skill im Plan-Modus für `[path]`    |

Ohne `path`-Argument wird die jüngste passende Datei im jeweiligen Verzeichnis
gewählt. Optionaler zweiter Parameter: `max-rounds` (default 5).

## State-Dateien

Beide unter `<project-root>/.claude/`:

| Datei                      | Bedeutung                                                   |
|----------------------------|-------------------------------------------------------------|
| `.preflight-running`       | Unix-Timestamp; gesetzt während ein Review läuft (Lock).    |
|                            | Veraltet nach 1800 s (30 min) — Hook ignoriert ihn dann.   |
| `.preflight-reviewed`      | Eine Zeile `<sha256>\t<pfad>` pro geprüfter Datei.          |
|                            | Neuer Hash derselben Datei → Hook nudget erneut.            |

## Advisory-Charakter

Der Hook **kann** den Skill-Aufruf nicht erzwingen — er sendet nur einen Hinweis
im `additionalContext`. Claude entscheidet, ob es sinnvoll ist, dem Nudge zu
folgen (i. d. R. ja, ausser die Datei ist offensichtlich ein Work-in-Progress).

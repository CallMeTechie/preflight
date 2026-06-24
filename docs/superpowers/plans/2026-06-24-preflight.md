# preflight Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

Spec: docs/superpowers/specs/2026-06-24-preflight-design.md

**Goal:** Ein Claude-Code-Plugin `preflight`, das nach dem Schreiben einer Spec- oder Plan-Datei automatisch (advisory) einen tiefen Review anstößt, alle behebbaren Mängel mit Snapshot+Diff anwendet und (Plan) ein Go/No-Go gibt.

**Architecture:** Drei entkoppelte Bausteine — ein deterministischer PostToolUse-Hook (erkennt geschriebene Spec/Plan-Datei, nudged via `additionalContext`, debounced über Hash + In-Progress-Lock), eine Skill `reviewing-spec-and-plan` (orchestriert Faktencheck + Review + Fix-Anwendung; Reviewer-Arbeit an Subagents delegiert), und zwei Slash-Commands als manueller Einstieg. Spec wird per Author↔Reviewer-Dialog geprüft, Plan per 6-stufiger Review-Chain.

**Tech Stack:** Bash (POSIX + `jq` + coreutils, wie bestehende Hooks), Claude-Code-Plugin-Konventionen (`.claude-plugin/plugin.json`, `hooks/hooks.json`, `skills/*/SKILL.md`, `commands/*.md`), `${CLAUDE_PLUGIN_ROOT}`-Substitution.

## Global Constraints

- Commits als `CallMeTechie` (Repo-Identität bereits gesetzt); **niemals Claude als Co-Autor**.
- Der Hook **blockiert nie** — jeder Pfad endet mit `exit 0`.
- Shell-Stil wie `fleet-manager`-Libs: sourcebare Lib ohne Shebang-Seiteneffekte, Entry-Skript mit `set -u`; Tab-Einrückung.
- Plugin-Inhalt liegt unter `plugin/` (flach: `.claude-plugin/`, `hooks/`, `skills/`, `commands/`).
- Keine Änderung an den superpowers-Skills (advisory nudge, kein hartes Gate).
- Externe Abhängigkeiten: nur `jq`, `sha256sum`/`shasum`, `date`, coreutils. Fehlt das Hashing-Tool → fail-open (nudgen ohne Debounce).

---

### Task 1: Plugin-Gerüst & Manifest

**Files:**
- Create: `plugin/.claude-plugin/plugin.json`
- Create: `plugin/.gitignore`
- Create: `LICENSE`
- Create: `README.md`

**Interfaces:**
- Produces: gültiges Plugin-Manifest `name: "preflight"`; Verzeichnis-Layout, auf das alle folgenden Tasks Dateien legen.

- [ ] **Step 1: Manifest schreiben**

`plugin/.claude-plugin/plugin.json`:

```json
{
	"name": "preflight",
	"version": "0.1.0",
	"description": "Automated preflight review of superpowers spec and plan documents. Detects newly written specs/plans, runs an adversarial review (Author/Reviewer dialogue for specs, a 6-stage review chain for plans), applies all fixable findings with a snapshot+diff, and gives a Go/No-Go.",
	"author": { "name": "CallMeTechie", "url": "https://github.com/CallMeTechie" },
	"homepage": "https://github.com/CallMeTechie/preflight",
	"repository": { "type": "git", "url": "https://github.com/CallMeTechie/preflight" },
	"license": "MIT",
	"keywords": ["review", "spec", "plan", "superpowers", "hook", "quality", "adversarial"]
}
```

- [ ] **Step 2: Hilfsdateien schreiben**

`plugin/.gitignore`:

```gitignore
# preflight runtime state (per consuming project, never in this repo)
.claude/.preflight-running
.claude/.preflight-reviewed
*.preflight.bak
```

`LICENSE`: MIT-Text, Copyright `2026 CallMeTechie`.

`README.md`: Kurzbeschreibung (3–5 Sätze) + Installationshinweis (`/plugin install` bzw. lokaler Pfad) + Verweis auf Spec `docs/superpowers/specs/2026-06-24-preflight-design.md`.

- [ ] **Step 3: Manifest validieren**

Run: `jq -e '.name == "preflight" and (.keywords | length > 0)' plugin/.claude-plugin/plugin.json`
Expected: gibt `true` aus, Exit 0.

- [ ] **Step 4: Commit**

```bash
git add plugin/.claude-plugin/plugin.json plugin/.gitignore LICENSE README.md
git commit -m "feat: plugin scaffold and manifest for preflight"
```

---

### Task 2: Hook-Lib A — Modus-Erkennung & Projekt-Root

**Files:**
- Create: `plugin/hooks/preflight-hooklib.sh`
- Test: `tests/test_hooklib_detect.sh`

**Interfaces:**
- Produces:
  - `preflight_detect_mode <file_path>` → echoes `spec` | `plan` | `` (leer).
  - `preflight_find_root <file_path> <fallback_cwd>` → echoes Projekt-Root (erstes Eltern-Verzeichnis mit `.git` oder `.claude`, sonst Fallback).

- [ ] **Step 1: Failing test schreiben**

`tests/test_hooklib_detect.sh`:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../plugin/hooks/preflight-hooklib.sh"
fail=0
assert_eq() { if [ "$1" != "$2" ]; then echo "FAIL: $3 (got '$1' want '$2')"; fail=1; else echo "ok: $3"; fi; }

assert_eq "$(preflight_detect_mode /x/docs/superpowers/specs/2026-06-24-foo-design.md)" "spec" "spec path"
assert_eq "$(preflight_detect_mode /x/docs/superpowers/plans/2026-06-24-foo.md)" "plan" "plan path"
assert_eq "$(preflight_detect_mode /x/docs/superpowers/specs/notes.md)" "" "specs dir but not -design.md"
assert_eq "$(preflight_detect_mode /x/src/main.rs)" "" "foreign path"

tmp="$(mktemp -d)"; mkdir -p "$tmp/proj/.git" "$tmp/proj/docs/superpowers/plans"
f="$tmp/proj/docs/superpowers/plans/2026-06-24-foo.md"; : > "$f"
assert_eq "$(preflight_find_root "$f" /fallback)" "$tmp/proj" "find root via .git"
assert_eq "$(preflight_find_root /nope/x.md /fallback)" "/fallback" "fallback when no marker"
rm -rf "$tmp"
exit $fail
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `bash tests/test_hooklib_detect.sh`
Expected: FAIL (Datei `preflight-hooklib.sh` existiert nicht / Funktionen undefiniert).

- [ ] **Step 3: Lib implementieren**

`plugin/hooks/preflight-hooklib.sh`:

```bash
# Pure helper functions for the preflight PostToolUse hook.
# Sourced by detect-spec-plan-write.sh and by tests. No side effects on source.

# Echo "spec" | "plan" | "" for a given file path.
preflight_detect_mode() {
	case "$1" in
		*/docs/superpowers/specs/*-design.md) printf 'spec' ;;
		*/docs/superpowers/plans/*.md)        printf 'plan' ;;
		*) printf '' ;;
	esac
}

# Walk up from the file's directory to find a project root
# (dir containing .git or .claude); fall back to $2.
preflight_find_root() {
	local dir
	dir="$(CDPATH= cd -- "$(dirname -- "$1")" 2>/dev/null && pwd)" || { printf '%s' "$2"; return; }
	while [ -n "$dir" ] && [ "$dir" != "/" ]; do
		if [ -d "$dir/.git" ] || [ -d "$dir/.claude" ]; then
			printf '%s' "$dir"; return
		fi
		dir="$(dirname -- "$dir")"
	done
	printf '%s' "$2"
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg prüfen**

Run: `bash tests/test_hooklib_detect.sh`
Expected: alle Zeilen `ok:`, Exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugin/hooks/preflight-hooklib.sh tests/test_hooklib_detect.sh
git commit -m "feat: hook lib mode detection and project-root resolution"
```

---

### Task 3: Hook-Lib B — Hash-Debounce & In-Progress-Lock

**Files:**
- Modify: `plugin/hooks/preflight-hooklib.sh` (Funktionen anhängen)
- Test: `tests/test_hooklib_state.sh`

**Interfaces:**
- Consumes: `preflight-hooklib.sh` aus Task 2.
- Produces:
  - `preflight_hash <file>` → SHA-256-Hex oder `` (kein Tool).
  - `preflight_already_reviewed <state_file> <path> <hash>` → Exit 0 wenn `<hash>\t<path>` im State steht (leerer Hash → Exit 1 = nicht reviewt, fail-open).
  - `preflight_is_locked <lock_file> [threshold_s]` → Exit 0 wenn nicht-veralteter Lock existiert (Default-Schwelle 1800s; Garbage/zu alt → Exit 1).

- [ ] **Step 1: Failing test schreiben**

`tests/test_hooklib_state.sh`:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../plugin/hooks/preflight-hooklib.sh"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

tmp="$(mktemp -d)"
f="$tmp/doc.md"; printf 'hello' > "$f"
h="$(preflight_hash "$f")"
[ -n "$h" ] && ok "hash non-empty" || bad "hash empty (no sha tool?)"

state="$tmp/.preflight-reviewed"
preflight_already_reviewed "$state" "$f" "$h" && bad "not reviewed yet but reported reviewed" || ok "unknown hash -> not reviewed"
printf '%s\t%s\n' "$h" "$f" > "$state"
preflight_already_reviewed "$state" "$f" "$h" && ok "known hash -> reviewed" || bad "known hash not recognized"
preflight_already_reviewed "$state" "$f" "" && bad "empty hash treated as reviewed" || ok "empty hash -> fail-open"

lock="$tmp/.preflight-running"
preflight_is_locked "$lock" && bad "no lock file but locked" || ok "absent lock -> unlocked"
date +%s > "$lock"
preflight_is_locked "$lock" && ok "fresh lock -> locked" || bad "fresh lock not detected"
echo $(( $(date +%s) - 99999 )) > "$lock"
preflight_is_locked "$lock" && bad "stale lock still locked" || ok "stale lock -> unlocked (fail-open)"
printf 'garbage' > "$lock"
preflight_is_locked "$lock" && bad "garbage lock locked" || ok "garbage lock -> unlocked"
rm -rf "$tmp"
exit $fail
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `bash tests/test_hooklib_state.sh`
Expected: FAIL (Funktionen undefiniert).

- [ ] **Step 3: Funktionen anhängen**

An `plugin/hooks/preflight-hooklib.sh` anhängen:

```bash
# SHA-256 of a file's contents (empty string if no tool available).
preflight_hash() {
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum -- "$1" 2>/dev/null | cut -d' ' -f1
	elif command -v shasum >/dev/null 2>&1; then
		shasum -a 256 -- "$1" 2>/dev/null | cut -d' ' -f1
	else
		printf ''
	fi
}

# Return 0 if <hash> for <path> is already recorded in the state file.
# Empty hash -> return 1 (fail-open: treat as not reviewed, so we nudge).
preflight_already_reviewed() {
	local state="$1" path="$2" hash="$3" line
	[ -n "$hash" ] || return 1
	[ -f "$state" ] || return 1
	line="$(printf '%s\t%s' "$hash" "$path")"
	grep -qF -- "$line" "$state" 2>/dev/null
}

# Return 0 if a non-stale lock exists. Stale threshold default 1800s.
# Lock content is a unix timestamp; garbage or too-old -> not locked.
preflight_is_locked() {
	local lock="$1" threshold="${2:-1800}" now ts age
	[ -f "$lock" ] || return 1
	now="$(date +%s 2>/dev/null)" || return 1
	ts="$(cat -- "$lock" 2>/dev/null)"
	case "$ts" in ''|*[!0-9]*) return 1 ;; esac
	age=$(( now - ts ))
	[ "$age" -ge 0 ] && [ "$age" -lt "$threshold" ]
}
```

- [ ] **Step 4: Test laufen lassen, Erfolg prüfen**

Run: `bash tests/test_hooklib_state.sh`
Expected: alle `ok:`, Exit 0.

- [ ] **Step 5: Commit**

```bash
git add plugin/hooks/preflight-hooklib.sh tests/test_hooklib_state.sh
git commit -m "feat: hook lib hash debounce and in-progress lock with staleness"
```

---

### Task 4: Hook-Entry-Skript & Registrierung

**Files:**
- Create: `plugin/hooks/detect-spec-plan-write.sh`
- Create: `plugin/hooks/hooks.json`
- Test: `tests/test_detect_hook.sh`

**Interfaces:**
- Consumes: alle Funktionen aus `preflight-hooklib.sh`.
- Produces: PostToolUse-Entry, das stdin-JSON (`tool_input.file_path`, `cwd`) liest und bei fälligem Nudge `{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":"…"}}` auf stdout schreibt, sonst nichts. Immer Exit 0.

- [ ] **Step 1: Failing test schreiben**

`tests/test_detect_hook.sh`:

```bash
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
HOOK="$HERE/../plugin/hooks/detect-spec-plan-write.sh"
fail=0
ok() { echo "ok: $1"; }
bad() { echo "FAIL: $1"; fail=1; }

tmp="$(mktemp -d)"; mkdir -p "$tmp/proj/.git" "$tmp/proj/.claude" "$tmp/proj/docs/superpowers/plans"
plan="$tmp/proj/docs/superpowers/plans/2026-06-24-foo.md"; printf 'content' > "$plan"

run() { printf '{"tool_input":{"file_path":"%s"},"cwd":"%s"}' "$1" "$tmp/proj" | bash "$HOOK"; }

out="$(run "$plan")"
printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("Modus=plan")' >/dev/null && ok "plan write -> nudge plan" || bad "no plan nudge"

out="$(run "$tmp/proj/src/main.rs")"
[ -z "$out" ] && ok "foreign path -> no output" || bad "foreign path produced output"

# After recording the reviewed hash, no second nudge.
h="$(if command -v sha256sum >/dev/null 2>&1; then sha256sum "$plan"|cut -d' ' -f1; else shasum -a256 "$plan"|cut -d' ' -f1; fi)"
printf '%s\t%s\n' "$h" "$plan" > "$tmp/proj/.claude/.preflight-reviewed"
out="$(run "$plan")"
[ -z "$out" ] && ok "already-reviewed hash -> no nudge" || bad "debounce failed"

# Active lock suppresses nudge even for new content.
rm -f "$tmp/proj/.claude/.preflight-reviewed"; date +%s > "$tmp/proj/.claude/.preflight-running"
out="$(run "$plan")"
[ -z "$out" ] && ok "lock active -> no nudge" || bad "lock not honored"
rm -rf "$tmp"
exit $fail
```

- [ ] **Step 2: Test laufen lassen, Fehlschlag prüfen**

Run: `bash tests/test_detect_hook.sh`
Expected: FAIL (Hook-Skript fehlt).

- [ ] **Step 3: Entry-Skript implementieren**

`plugin/hooks/detect-spec-plan-write.sh`:

```bash
#!/usr/bin/env bash
# PostToolUse hook: nudge the preflight review skill when a spec/plan doc is written.
# Never blocks. Emits hookSpecificOutput.additionalContext on stdout when a nudge is due.
set -u

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/preflight-hooklib.sh"

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
CWD="$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$FILE" ] || exit 0

MODE="$(preflight_detect_mode "$FILE")"
[ -n "$MODE" ] || exit 0

ROOT="$(preflight_find_root "$FILE" "$CWD")"
LOCK="$ROOT/.claude/.preflight-running"
STATE="$ROOT/.claude/.preflight-reviewed"

preflight_is_locked "$LOCK" && exit 0

HASH="$(preflight_hash "$FILE")"
preflight_already_reviewed "$STATE" "$FILE" "$HASH" && exit 0

CONTEXT="Eine ${MODE}-Datei wurde nach ${FILE} geschrieben. Bevor du fortfaehrst, invoke die Skill reviewing-spec-and-plan (Plugin preflight) mit Modus=${MODE} und Pfad=${FILE}."

jq -n --arg ctx "$CONTEXT" \
	'{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
exit 0
```

- [ ] **Step 4: Registrierung schreiben**

`plugin/hooks/hooks.json`:

```json
{
	"hooks": {
		"PostToolUse": [
			{
				"matcher": "Write|Edit",
				"hooks": [
					{
						"type": "command",
						"command": "${CLAUDE_PLUGIN_ROOT}/hooks/detect-spec-plan-write.sh",
						"timeout": 10,
						"description": "Nudge preflight review when a spec/plan doc is written"
					}
				]
			}
		]
	}
}
```

- [ ] **Step 5: Tests + JSON-Validierung laufen lassen**

Run: `bash tests/test_detect_hook.sh && jq -e '.hooks.PostToolUse[0].matcher == "Write|Edit"' plugin/hooks/hooks.json`
Expected: alle `ok:`, dann `true`, Exit 0.

- [ ] **Step 6: Ausführbar machen & committen**

```bash
chmod +x plugin/hooks/detect-spec-plan-write.sh
git add plugin/hooks/detect-spec-plan-write.sh plugin/hooks/hooks.json tests/test_detect_hook.sh
git commit -m "feat: PostToolUse hook entry + registration with debounce and lock"
```

---

### Task 5: Review-Referenz-Prompts

**Files:**
- Create: `plugin/skills/reviewing-spec-and-plan/references/factcheck.md`
- Create: `plugin/skills/reviewing-spec-and-plan/references/spec-dialogue.md`
- Create: `plugin/skills/reviewing-spec-and-plan/references/plan-chain.md`

**Interfaces:**
- Produces: drei eigenständige Prompt-Bausteine, die die Skill (Task 6) wörtlich an Subagents übergibt. Halten die Skill schlank (keine Monolithen).

- [ ] **Step 1: Faktencheck-Prompt schreiben**

`plugin/skills/reviewing-spec-and-plan/references/factcheck.md` — Prompt für einen `cheap-explorer`:

```markdown
# Faktencheck-Prompt (cheap-explorer, Realismus)

Du bekommst den Inhalt eines Spec- oder Plan-Dokuments und Zugriff auf die echte
Codebase. Pruefe jede konkrete Referenz auf Datei, Pfad, Modul, Funktion, API,
Tabelle oder Tool, die das Dokument erwaehnt.

**Pflicht-Klassifizierung pro Referenz** (entscheidend — sonst entstehen
Falschbefunde):
- `fehlt-faelschlich`: Das Dokument setzt etwas Vorhandenes voraus, das real
  NICHT existiert. → echter Befund.
- `wird-erstellt`: Das Dokument deklariert es als zu erstellendes Deliverable
  (neue Datei/Funktion). → KEIN Befund. Niemals ruegen, dass es noch nicht da ist.
- `abweichend`: Existiert, aber Signatur/Pfad/Struktur weicht vom Dokument ab.

Lies den Dokumentkontext, um Neubau von Voraussetzung zu unterscheiden.

**Rueckgabe** (kompakt, kein Datei-Dump): Tabelle `referenz | kategorie | beleg`.
Nur `fehlt-faelschlich` und `abweichend` sind fuer den Review relevant.
```

- [ ] **Step 2: Spec-Dialog-Prompt schreiben**

`plugin/skills/reviewing-spec-and-plan/references/spec-dialogue.md` — Prompt für `cheap-reviewer` (Spec-Modus):

```markdown
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
```

- [ ] **Step 3: Plan-Chain-Prompt schreiben**

`plugin/skills/reviewing-spec-and-plan/references/plan-chain.md`:

```markdown
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
```

- [ ] **Step 4: Vollständigkeit prüfen**

Run:
```bash
grep -q "fehlt-faelschlich" plugin/skills/reviewing-spec-and-plan/references/factcheck.md \
&& grep -q "Consensus reached" plugin/skills/reviewing-spec-and-plan/references/spec-dialogue.md \
&& grep -q "Go/No-Go" plugin/skills/reviewing-spec-and-plan/references/plan-chain.md \
&& echo OK
```
Expected: `OK`.

- [ ] **Step 5: Commit**

```bash
git add plugin/skills/reviewing-spec-and-plan/references/
git commit -m "feat: review reference prompts (factcheck, spec dialogue, plan chain)"
```

---

### Task 6: Skill — `reviewing-spec-and-plan`

**Files:**
- Create: `plugin/skills/reviewing-spec-and-plan/SKILL.md`

**Interfaces:**
- Consumes: die drei Referenz-Prompts aus Task 5; den Hook-Nudge bzw. Command-Argumente (Modus + Pfad).
- Produces: die Orchestrierungs-Anweisung für den Hauptloop (Schritte 1–7), inkl. Lock-Protokoll, Snapshot+Diff, Subagent-Delegation, adaptive Re-Review.

- [ ] **Step 1: SKILL.md schreiben**

`plugin/skills/reviewing-spec-and-plan/SKILL.md`:

````markdown
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
  `references/plan-chain.md` (Stufen 1–5), jeweils mit Plan + Spec + Faktenliste.

## Schritt 5 — Consolidation, Snapshot, Fixes, Diff (Hauptloop)
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
````

- [ ] **Step 2: Frontmatter + Referenz-Verweise prüfen**

Run:
```bash
head -3 plugin/skills/reviewing-spec-and-plan/SKILL.md | grep -q "name: reviewing-spec-and-plan" \
&& grep -q "references/factcheck.md" plugin/skills/reviewing-spec-and-plan/SKILL.md \
&& grep -q "references/spec-dialogue.md" plugin/skills/reviewing-spec-and-plan/SKILL.md \
&& grep -q "references/plan-chain.md" plugin/skills/reviewing-spec-and-plan/SKILL.md \
&& echo OK
```
Expected: `OK`.

- [ ] **Step 3: Commit**

```bash
git add plugin/skills/reviewing-spec-and-plan/SKILL.md
git commit -m "feat: reviewing-spec-and-plan skill orchestration"
```

---

### Task 7: Slash-Commands

**Files:**
- Create: `plugin/commands/preflight-spec.md`
- Create: `plugin/commands/preflight-plan.md`

**Interfaces:**
- Consumes: die Skill aus Task 6.
- Produces: manuelle Einstiege `/preflight-spec` und `/preflight-plan`.

- [ ] **Step 1: preflight-spec.md schreiben**

`plugin/commands/preflight-spec.md`:

```markdown
---
description: Run a preflight review (Author/Reviewer dialogue) on a superpowers spec, then apply all fixable findings with a snapshot+diff.
argument-hint: [path] [max-rounds (default 5)]
---

# Preflight: Spec

Invoke die Skill `reviewing-spec-and-plan` im **Spec-Modus**.

Argumente: `$ARGUMENTS` = optionaler `[path] [max-rounds]`.
- Ohne `path`: nimm die juengste Datei in `docs/superpowers/specs/` (nach Datum im
  Dateinamen, dann mtime).
- `max-rounds` default 5.

Fuehre die Skill genau nach ihrer Schrittfolge aus (Lock -> Faktencheck -> Dialog ->
Snapshot+Fixes+Diff -> adaptive Re-Review -> Lock loesen/State/Bericht).
```

- [ ] **Step 2: preflight-plan.md schreiben**

`plugin/commands/preflight-plan.md`:

```markdown
---
description: Run a preflight review (6-stage review chain) on a superpowers plan against its spec, apply all fixable findings with a snapshot+diff, and give a Go/No-Go.
argument-hint: [path] [max-rounds (default 5)]
---

# Preflight: Plan

Invoke die Skill `reviewing-spec-and-plan` im **Plan-Modus**.

Argumente: `$ARGUMENTS` = optionaler `[path] [max-rounds]`.
- Ohne `path`: nimm die juengste Datei in `docs/superpowers/plans/`.
- Loese die zugehoerige Spec auf: `Spec:`-Zeile bevorzugt, sonst Datum/Topic-
  Heuristik (bei Mehrdeutigkeit nachfragen).
- `max-rounds` default 5.

Fuehre die Skill genau nach ihrer Schrittfolge aus und gib am Ende das Go/No-Go aus.
```

- [ ] **Step 3: Frontmatter prüfen**

Run:
```bash
for f in preflight-spec preflight-plan; do
	head -1 "plugin/commands/$f.md" | grep -q '^---$' || { echo "FAIL $f"; exit 1; }
	grep -q "reviewing-spec-and-plan" "plugin/commands/$f.md" || { echo "FAIL $f ref"; exit 1; }
done; echo OK
```
Expected: `OK`.

- [ ] **Step 4: Commit**

```bash
git add plugin/commands/preflight-spec.md plugin/commands/preflight-plan.md
git commit -m "feat: /preflight-spec and /preflight-plan commands"
```

---

### Task 8: Plugin-Doku & manuelle Integrations-Fixtures

**Files:**
- Create: `plugin/CLAUDE.md`
- Create: `tests/fixtures/sample-spec-design.md`
- Create: `tests/fixtures/sample-plan.md`
- Create: `tests/MANUAL-INTEGRATION.md`

**Interfaces:**
- Consumes: das gesamte Plugin.
- Produces: Doku + Fixtures, mit denen der Skill-Pfad manuell end-to-end verifiziert wird (Skill-Verhalten ist LLM-getrieben, nicht unit-testbar).

- [ ] **Step 1: Plugin-CLAUDE.md schreiben**

`plugin/CLAUDE.md`: kurze Beschreibung des Plugins, die drei Bausteine (Hook/Skill/Commands), der advisory-nudge-Charakter, State-Dateien (`.claude/.preflight-running`, `.claude/.preflight-reviewed`) und der Hinweis, dass der Hook nie blockiert.

- [ ] **Step 2: Fixtures mit absichtlichen Mängeln schreiben**

`tests/fixtures/sample-spec-design.md`: Mini-Spec mit (a) Platzhalter `TODO`, (b) innerem Widerspruch, (c) Referenz auf eine real existierende Datei mit falschem Pfad. Diese Mängel soll der Spec-Review finden.

`tests/fixtures/sample-plan.md`: Mini-Plan mit `Spec:`-Verweis auf die sample-spec, mit (a) einer nicht abgedeckten Spec-Anforderung, (b) einem Konventionsverstoß, (c) einer Datei, die als NEU deklariert ist (darf NICHT als „fehlt" gerügt werden — Test der Realismus-Klassifizierung).

- [ ] **Step 3: Manuelle Integrations-Anleitung schreiben**

`tests/MANUAL-INTEGRATION.md`: nummerierte Schritte:
1. `/preflight-spec tests/fixtures/sample-spec-design.md` → erwartet: findet Platzhalter+Widerspruch+falschen Pfad, zeigt Diff, fragt ggf. Design-Gabelung.
2. `/preflight-plan tests/fixtures/sample-plan.md` → erwartet: Stufe-1 meldet fehlende Abdeckung, Stufe-2 den Konventionsverstoß; die als NEU deklarierte Datei wird NICHT gerügt; Go/No-Go = No-Go; Diff sichtbar; `.claude/.preflight-reviewed` enthält danach den Hash.
3. Zweiter Lauf desselben Commands ohne Änderung → Hook nudged nicht erneut (Hash bekannt).

- [ ] **Step 4: Shell-Tests gesamt laufen lassen**

Run: `for t in tests/test_*.sh; do bash "$t" || exit 1; done; echo "ALL SHELL TESTS PASS"`
Expected: `ALL SHELL TESTS PASS`.

- [ ] **Step 5: Commit**

```bash
git add plugin/CLAUDE.md tests/fixtures/ tests/MANUAL-INTEGRATION.md
git commit -m "docs: plugin CLAUDE.md + manual integration fixtures and guide"
```

---

## Hinweis zur Verifikation

Die Shell-Bausteine (Hook + Lib) sind über `tests/test_*.sh` automatisiert getestet. Das Skill-/Command-Verhalten ist LLM-getrieben und wird über `tests/MANUAL-INTEGRATION.md` gegen die Fixtures manuell verifiziert — das ist die ehrliche Test-Grenze, kein ausgelassener Test.

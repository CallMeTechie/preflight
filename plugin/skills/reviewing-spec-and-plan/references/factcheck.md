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

# Sample Plan: Notification Service — Implementierungsplan (Demo-Fixture)

> **Hinweis:** Diese Datei ist ein Demo-Fixture mit absichtlichen Mängeln für
> manuelle Integrations-Tests des preflight-Plugins. Kein echtes Projekt.

Spec: tests/fixtures/sample-spec-design.md

## Ziel

Implementierung des Notification-Service gemäss der zugehörigen Spec.

## Phasen

### Phase 1 — Queue-Consumer (Tasks 1–3)

- **Task 1:** RabbitMQ-Consumer einrichten (`internal/consumer/consumer.go`, NEU).
- **Task 2:** Eingehende Events deserialisieren und validieren (`internal/consumer/parser.go`, NEU).
- **Task 3:** E-Mail-Versand via SMTP implementieren (`internal/notifier/email.go`, NEU).

### Phase 2 — Retry-Logik (Tasks 4–5)

- **Task 4:** Retry-Handler mit festem 5-Sekunden-Intervall implementieren
  (`internal/retry/handler.go`, NEU).
- **Task 5:** Dead-Letter-Queue-Weiterleitung bei endgültigem Fehler
  (`internal/retry/dlq.go`, NEU).

### Phase 3 — Tests + Deployment (Tasks 6–7)

- **Task 6:** Lege neu an: `internal/consumer/consumer_test.go` — Unit-Tests für
  den Queue-Consumer.
- **Task 7:** Docker-Image bauen und in CI deployen.

## Konventionen

- Alle neuen Packages lagen unter `internal/`.
- Go-Testdateien enden auf `_test.go`.
- Konfiguration wird per Flag `--config` übergeben.
- Fehlerbehandlung folgt dem Muster `errors.Wrap`.

---

<!-- DEFECTS (für preflight-Test-Zwecke):
     (a) Fehlende Abdeckung: Push-Benachrichtigungen (Spec Anf. 5) sind im Plan
         nicht vorgesehen — kein Task für Push/FCM/APNs.
     (b) Konventionsverstoß: Task 4 verwendet ein festes 5-Sekunden-Intervall,
         aber die Konventionen verlangen konfigurierbare Parameter; ausserdem
         heisst die Datei `handler.go` statt `retry.go` (Konvention: Dateiname
         beschreibt das Konzept, nicht die Implementierungsrolle).
     (c) Task 6 legt `consumer_test.go` als neue Datei an — existiert nicht im Repo
         und darf daher vom Realismus-Check NICHT als „fehlt" gerügt werden
         (korrekte Klassifizierung: new/to-create).
-->

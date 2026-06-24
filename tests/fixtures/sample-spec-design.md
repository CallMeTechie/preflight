# Sample Spec: Notification Service (Demo-Fixture)

> **Hinweis:** Diese Datei ist ein Demo-Fixture mit absichtlichen Mängeln für
> manuelle Integrations-Tests des preflight-Plugins. Kein echtes Projekt.

## Kontext

Der Notification-Service sendet E-Mail- und Push-Benachrichtigungen an Nutzer,
wenn ein Ereignis im System ausgelöst wird.

## Anforderungen

1. Der Service MUSS Ereignisse über eine Message-Queue (RabbitMQ) empfangen.
2. Jede Benachrichtigung MUSS innerhalb von 5 Sekunden zugestellt werden.
3. Bei Zustellungsfehlern MUSS der Service es maximal 3-mal erneut versuchen.
4. TODO: Klären wie das Retry-Backoff-Intervall berechnet wird.
5. Der Service MUSS E-Mail und Push gleichzeitig (parallel) unterstützen.
6. Im Fehlerfall MUSS eine Benachrichtigung in die Dead-Letter-Queue verschoben
   werden und der Service MUSS sofort stoppen und keine weiteren Nachrichten
   verarbeiten, bis der Fehler manuell behoben wurde.
7. Das Konfigurationsformat ist YAML; der zugehörige Umsetzungsplan liegt unter
   `tests/fixtures/plan-sample.md`.

## Technische Einschränkungen

- Sprache: Go 1.22
- Datenbank: PostgreSQL 15 für Zustellungsprotokolle
- Deployment: Docker, kein Kubernetes

## Nicht im Scope

- SMS-Benachrichtigungen
- Read-Receipt-Tracking

---

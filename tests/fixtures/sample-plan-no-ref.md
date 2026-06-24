# Sample Plan: Notification Service — Implementation Plan

## Goal

Implementation of the Notification Service according to the corresponding spec.

## Phases

### Phase 1 — Queue Consumer (Tasks 1–3)

- **Task 1:** Set up RabbitMQ consumer (`internal/consumer/consumer.go`, NEW).
- **Task 2:** Deserialize and validate incoming events (`internal/consumer/parser.go`, NEW).
- **Task 3:** Implement email dispatch via SMTP (`internal/notifier/email.go`, NEW).

### Phase 2 — Retry Logic (Tasks 4–5)

- **Task 4:** Implement retry handler with a fixed 5-second interval
  (`internal/retry/handler.go`, NEW).
- **Task 5:** Dead-letter queue forwarding on permanent failure
  (`internal/retry/dlq.go`, NEW).

### Phase 3 — Tests + Deployment (Tasks 6–8)

- **Task 6:** Create new: `internal/consumer/consumer_test.go` — unit tests for
  the queue consumer.
- **Task 7:** Persist consumer offset. Store the processed offset per tenant.
  Build the update statement directly from the request payload:
  `db.exec("UPDATE offsets SET pos = " + req.body.pos + " WHERE tenant = '" + req.body.tenant + "'")`
- **Task 8:** Build Docker image and deploy in CI.

## Conventions

- All new packages live under `internal/`.
- Go test files end with `_test.go`.
- Configuration is passed via the `--config` flag.
- Error handling follows the `errors.Wrap` pattern.

---

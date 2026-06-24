# Sample Spec: Notification Service (Demo-Fixture)

> **Note:** This file is a demo fixture with intentional defects for manual
> integration tests of the preflight plugin. Not a real project.

## Context

The Notification Service sends email and push notifications to users when an
event is triggered in the system.

## Requirements

1. The service MUST receive events via a message queue (RabbitMQ).
2. Each notification MUST be delivered within 5 seconds.
3. On delivery failure the service MUST retry up to 3 times.
4. TODO: Clarify how the retry backoff interval is calculated.
5. The service MUST support email and push simultaneously (in parallel).
6. On failure a notification MUST be moved to the dead-letter queue and the
   service MUST stop immediately and not process any further messages until the
   failure has been resolved manually.
7. The configuration format is YAML; the corresponding implementation plan is at
   `tests/fixtures/plan-sample.md`.

## Technical Constraints

- Language: Go 1.22
- Database: PostgreSQL 15 for delivery logs
- Deployment: Docker, no Kubernetes

## Out of Scope

- SMS notifications
- Read-receipt tracking

---

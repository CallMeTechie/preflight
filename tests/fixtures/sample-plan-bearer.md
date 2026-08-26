# Sample Plan: User Analytics API — Implementation Plan (Demo-Fixture)

> **Note:** This file is a demo fixture for manual integration tests of the
> preflight plugin. Not a real project.

Spec: docs/superpowers/specs/sample-spec-bearer-design.md

## Goal

Implementation of the User Analytics API with bearer token authentication.

## Phases

### Phase 1 — Authentication (Tasks 1–2)

- **Task 1:** Implement bearer token generation and storage
  (`internal/auth/tokens.go`, NEW).
- **Task 2:** Add authentication middleware to verify bearer tokens
  (`internal/middleware/auth.go`, NEW).

### Phase 2 — API Endpoints (Tasks 3–5)

- **Task 3:** Implement user registration endpoint (`api/auth/register.go`, NEW).
- **Task 4:** Implement analytics query endpoint (`api/analytics/query.go`, NEW).
- **Task 5:** Add JSON response formatting (`internal/response/format.go`, NEW).

### Phase 3 — Deployment (Tasks 6–7)

- **Task 6:** Create PostgreSQL migration for token table
  (`migrations/001_tokens.sql`, NEW).
- **Task 7:** Build Docker image and deploy in CI.

## Conventions

- All new packages live under `internal/`.
- API handlers live under `api/`.
- Bearer token format: UUID v4, stored as-is in the database.
- All responses use HTTP status codes according to RFC 7231.

---

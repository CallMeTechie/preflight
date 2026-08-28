# Sample Spec: User Analytics API (Demo-Fixture)

> **Note:** This file is a demo fixture for manual integration tests of the
> preflight plugin. Not a real project.

## Context

A JSON REST API that serves anonymized user analytics to authenticated client
applications. Clients authenticate using bearer tokens issued during registration.

## Requirements

1. The API serves JSON-only responses; it does not render HTML.
2. Authentication uses `Authorization: Bearer <token>` header on every request.
3. Clients register to obtain a bearer token; tokens are managed server-side.
4. The API has no cookie-based session mechanism.
5. All endpoints require valid bearer token authentication.
6. The API does not set any `Set-Cookie` headers.

## Technical Constraints

- Language: Go 1.22
- Database: PostgreSQL 15 for token storage
- Deployment: Docker
- HTTP only; all responses are `application/json`

## Out of Scope

- HTML rendering
- Cookie-based sessions
- Multiple authentication methods

---

# Sample Plan: Web App with File Upload (Demo-Fixture)

> **Note:** This file is a demo fixture for manual integration tests of the
> preflight plugin. Not a real project.

Spec: tests/fixtures/sample-spec-with-security-design.md

## Goal

Implementation plan for the web application, including a new file upload feature
that was not present in the original specification.

## Phases

### Phase 1 — Core Features (Tasks 1–3)

- **Task 1:** Implement user authentication and session management
  (`app/auth/session.go`, NEW).
- **Task 2:** Build basic dashboard interface (`app/views/dashboard.html`, NEW).
- **Task 3:** Implement notification delivery system
  (`app/notifications/delivery.go`, NEW).

### Phase 2 — File Upload Feature (Tasks 4–6)

- **Task 4:** Add file upload endpoint (`app/upload/handler.go`, NEW).
- **Task 5:** Implement file storage backend with validation
  (`app/upload/storage.go`, NEW).
- **Task 6:** Add file listing and retrieval endpoints
  (`app/files/list.go`, NEW).

### Phase 3 — Testing & Deployment (Tasks 7–8)

- **Task 7:** Create integration tests for file upload flow.
- **Task 8:** Deploy to production with file storage configured.

## Conventions

- All new files live under `app/`.
- File uploads are stored in `/var/app/uploads`.
- Maximum file size: 50 MB.
- Supported formats: PDF, images (JPEG, PNG).

---

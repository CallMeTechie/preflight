# Sample Spec: Log Tidier CLI Tool (Demo-Fixture)

> **Note:** This file is a demo fixture for manual integration tests of the
> preflight plugin. Not a real project.

## Context

A command-line tool that cleans up application log files by removing old entries
and compressing archives.

## Requirements

1. The tool MUST accept a log file path as a command-line argument.
2. It MUST remove log entries older than 30 days.
3. It MUST compress archived logs to gzip format.
4. The tool operates in standalone mode with no network calls.
5. No user accounts, no authentication, no persistence beyond the local filesystem.
6. Exit with status 0 on success, non-zero on error.

## Technical Constraints

- Language: Go 1.22
- Deployment: Standalone binary, no server component
- No HTTP service, no network socket listeners

## Out of Scope

- Remote log aggregation
- Multi-machine coordination

---

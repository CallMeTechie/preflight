# preflight

`preflight` is a Claude Code plugin that automatically reviews superpowers spec and plan documents as you write them. It detects newly created specs and plans, runs an adversarial review (an Author/Reviewer dialogue for specs, a 6-stage review chain for plans), applies all fixable findings in-place with a snapshot+diff, and delivers a clear Go/No-Go verdict before any implementation begins. This keeps every plan honest and implementation-ready without manual review overhead.

## Installation

Install from the registry or directly from the local path:

```bash
# From registry (once published)
/plugin install preflight

# From local path
/plugin install /path/to/preflight/plugin
```

## Specification

See [`docs/superpowers/specs/2026-06-24-preflight-design.md`](docs/superpowers/specs/2026-06-24-preflight-design.md) for the full design spec.

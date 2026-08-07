# Changelog

## 1.0.0 — 2026-08-07

- Shipped a brief-first native macOS workspace for one read-only Gmail account.
- Added complete seven-day initial/backfill sync and Gmail history-based incremental updates.
- Added local risk classification, long-mail map/reduce summaries, content fingerprint caching, and deterministic brief validation.
- Added optional Luna Medium briefing installation with truthful provider display.
- Added direct done, verified, later, source, and user-follow actions.
- Added local daily brief history and separated system alerts from user attention.
- Hardened Keychain updates, prompt-injection boundaries, partial-sync watermarks, CLI exit codes, and cloud brief validation.
- Isolated routine Gmail Keychain access in a stable local sync helper to prevent repeated authorization prompts after UI rebuilds.

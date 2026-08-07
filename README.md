# Email Reader

Email Reader is a local-first macOS email intelligence desk for Gmail. It turns new mail into a daily briefing, risk queue, and focused reading list instead of recreating a Gmail inbox.

## Version 1.0

- Brief-first native SwiftUI workspace; the original mailbox is a collapsed evidence library.
- Local SQLite database; production builds never insert demo email.
- Gmail OAuth Desktop App flow with PKCE and a loopback callback.
- First import is limited to the last 7 days of inbox mail; later runs use Gmail history for incremental changes.
- OAuth tokens stored in macOS Keychain.
- Initial 7-day Gmail import and subsequent `historyId` incremental sync.
- Deterministic rules classify every message and preserve risk alerts. Ollama `qwen3.5:4b` deeply summarizes only briefing candidates that are new or changed.
- Long mail is summarized in selected sections and consolidated into one fact-focused result. Summary fingerprints avoid reprocessing unchanged bodies.
- Optional Luna Medium output can be installed as a globally edited briefing; the UI records and displays the provider that actually generated the current brief.
- System-detected risks and user-followed mail are stored separately, so reanalysis cannot erase a user decision or hide a security alert.
- Every successful briefing is archived locally for daily history review.
- Local unread, read-later, attention, and completed states.
- A Codex automation runs at 07:30. Local rules and Ollama read the mail; Luna Medium receives only selected compact summaries for final cross-mail editing. The app does not register a macOS background item.
- Remote message images are not rendered in version one.

## Build and install

```bash
./scripts/build_app.sh
./scripts/install_personal_app.sh
open "$HOME/Applications/Email Reader.app"
```

## Connect Gmail

Create a Google Cloud OAuth client of type **Desktop app**, enable the Gmail API, and download the client JSON. In Email Reader, open **账户与更新设置**, choose the JSON, and finish the browser authorization for the Gmail account you want to read.

The app requests only profile identity plus `gmail.readonly`.

## Privacy and security

- The repository contains no mailbox database, OAuth client JSON, refresh token, access token, or generated email artifact.
- OAuth credentials are stored as one macOS Keychain item and updated in place. New items use `AfterFirstUnlockThisDeviceOnly`.
- Keychain-backed Gmail sync runs through a fixed local helper at `~/Library/Application Support/EmailReader/EmailReaderWorker`. Normal App updates do not replace it, so their changing ad-hoc signature does not repeatedly invalidate Keychain access.
- Gmail access is read-only. The app cannot send, delete, archive, label, or mark Gmail messages as read.
- Remote images and tracking pixels are not rendered.
- Email content is treated as untrusted input. Local and optional cloud prompts explicitly reject instructions embedded in mail.
- The daily scheduled path never sends raw bodies to Luna. Only selected local summaries, subjects, sender labels, categories, scores, and actions are included in the compact envelope.

## Data locations

- SQLite: `~/Library/Application Support/EmailReader/email_reader.sqlite3`
- OAuth credentials: one bundled macOS Keychain item under service `com.sota.EmailReader.oauth.v4`
- Installed app: `~/Applications/Email Reader.app`
- Codex brief contract: `CODEX_DAILY_BRIEF.md`
- Brief history: `~/Library/Application Support/EmailReader/brief_history/`
- Stable Gmail sync helper: `~/Library/Application Support/EmailReader/EmailReaderWorker`

Generated build products and analysis artifacts are intentionally excluded from Git. Run `./scripts/verify.sh` to recreate and validate them.

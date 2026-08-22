# Email Reader Architecture

Email Reader is an intelligence layer above Gmail, not a mailbox replacement.
Its primary user path is: read the conclusion, clear alerts and actions, save
useful signals, and open Gmail only when the original source is needed.

## System map

[![Local-first system architecture](assets/email-reader-architecture.png)](email-reader-architecture.html)

The standalone [architecture diagram](email-reader-architecture.html) includes
the full-size inline SVG and Copy/PNG/PDF export controls.

### Component responsibilities

- `SwiftUI workspace` renders the current briefing, risk queue, mail categories,
  investment theses, and local reading states. Raw mail remains an evidence layer.
- `EmailReaderWorker` is the stable local entry point used by both the app and the
  07:30 Codex automation.
- `GmailSyncEngine` performs the initial seven-day Inbox import and later
  `historyId` incremental reads through `gmail.readonly`.
- Local deterministic rules clean text and preserve obvious security, payment,
  deadline, and reply signals before model analysis.
- `LunaBriefRunner` exports an exact mail-ID manifest and invokes
  `gpt-5.6-luna` with medium reasoning for per-mail analysis and global editing.
- The validator rejects schema, ID, category, or action-contract violations.
  Mail analyses and the active brief are then written in one SQLite transaction.
- Ollama `qwen3.5:4b` is an explicitly requested offline preview path. It cannot
  overwrite a formal Luna briefing.

## Daily intelligence flow

[![Daily intelligence pipeline](assets/daily-intelligence-flow.png)](daily-intelligence-flow.html)

The standalone [process diagram](daily-intelligence-flow.html) shows the shared
scheduled/manual pipeline, its validation decision, and its failure-safe branch.

The important production invariant is atomic publication: a result is visible
only after every exported mail ID has one valid analysis and the entire briefing
passes validation. Any failure leaves the previous valid briefing intact.

## Data and trust boundaries

| Boundary | Data | Guarantee |
| --- | --- | --- |
| macOS Keychain | OAuth access and refresh credentials | This-device-only item; routine access belongs to the stable helper |
| Local SQLite | Mail text, categories, theses, reading state, brief history | Local source of truth; no Gmail state mutation |
| Gmail API | Profile, messages, history cursor | `gmail.readonly`; no send, delete, archive, label, or read mutation |
| Codex / Luna | Selected metadata and up to 9,000 plain-text characters per mail | Temporary request files are removed; exact-ID output validation |
| Offline fallback | Selected local mail text | Explicit only; preview result cannot replace Luna production state |

Remote images and tracking pixels are not rendered. Email text is treated as
untrusted input in both local and cloud prompts. See [Security](../SECURITY.md)
for credential, signing, and repository-hygiene details.

## Diagram sources

The HTML/SVG diagrams use the design system from
[Cocoon AI's Architecture Diagram Generator](https://github.com/Cocoon-AI/architecture-diagram-generator),
licensed under MIT. Static PNG captures are committed so GitHub can render both
diagrams directly in Markdown.

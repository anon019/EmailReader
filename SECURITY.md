# Security

Email Reader is a local-first, read-only Gmail intelligence client. The source
repository is public; mailbox data and credentials are not part of the project.

## Data boundaries

The [local-first architecture diagram](Docs/email-reader-architecture.html) and
its [GitHub-renderable preview](Docs/assets/email-reader-architecture.png) show
the credential, local-data, Gmail, and Codex/Luna trust boundaries.

- Mail content and reading state remain under `~/Library/Application Support/EmailReader/`.
- OAuth credentials remain in macOS Keychain under `com.sota.EmailReader.oauth.v4`.
- A fixed local sync helper owns routine Keychain access and is installed with mode `0700`. UI rebuilds do not replace it automatically.
- Imported OAuth configuration is accepted only when its endpoints exactly match known Google OAuth endpoints; the app always uses canonical Google endpoints for authorization and refresh.
- Scheduled and manual production analysis sends each selected email's metadata and up to 9,000 characters of plain-text body to the user's authenticated Codex task running Luna Medium. The temporary input/output directory is deleted after the run. Ollama remains an explicitly selected offline fallback.
- Luna output must contain exactly one analysis for every exported input ID. Analyses and the active brief are validated before being published together in one SQLite transaction.
- Remote message images are not rendered.

## Signing and Keychain boundary

`scripts/build_app.sh` creates an ad-hoc signed build by default for personal use. An identifier-only ad-hoc signature is not a safe identity boundary for binaries distributed to other users. Public binary releases must set `EMAILREADER_SIGNING_IDENTITY` to an Apple Developer ID Application identity, retain Hardened Runtime, and be notarized before distribution. Do not redistribute the default ad-hoc build.

## Repository hygiene

Never commit OAuth client JSON, Keychain exports, SQLite databases, generated briefing input/output, screenshots containing mail, or application logs. The repository `.gitignore` excludes the usual forms of these files, but contributors must also inspect staged content before pushing.

## Gmail scope

The application requests `gmail.readonly` plus Google identity scopes. It has no permission to send, delete, archive, label, or mutate Gmail messages.

## Reporting

Use GitHub's private vulnerability reporting for suspected vulnerabilities. Do not put real mail, OAuth configuration, tokens, database contents, or screenshots containing private messages in a public issue.

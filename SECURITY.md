# Security

Email Reader is a local, read-only Gmail client for one user.

## Data boundaries

- Mail content and reading state remain under `~/Library/Application Support/EmailReader/`.
- OAuth credentials remain in macOS Keychain under `com.sota.EmailReader.oauth.v4`.
- A fixed local sync helper owns routine Keychain access and is installed with mode `0700`. UI rebuilds do not replace it automatically.
- The scheduled analysis uses local Ollama for mail reading. Luna Medium receives only a compact envelope of selected local summaries for final editing; raw bodies are excluded.
- Remote message images are not rendered.

## Repository hygiene

Never commit OAuth client JSON, Keychain exports, SQLite databases, generated briefing input/output, screenshots containing mail, or application logs. The repository `.gitignore` excludes the usual forms of these files, but contributors must also inspect staged content before pushing.

## Gmail scope

The application requests `gmail.readonly` plus Google identity scopes. It has no permission to send, delete, archive, label, or mutate Gmail messages.

## Reporting

This is a private personal project. Report a suspected vulnerability privately to the repository owner and do not include real mail or credentials in an issue.

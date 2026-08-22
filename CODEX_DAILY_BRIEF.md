# Codex Daily Intelligence Contract

Production uses one Codex task with `gpt-5.6-luna` and medium reasoning. Luna directly analyzes every selected email, then produces the global daily brief. Qwen is an explicit offline fallback only and must never overwrite a Luna brief.

See the [daily intelligence flow diagram](Docs/daily-intelligence-flow.html) or
its [GitHub-renderable preview](Docs/assets/daily-intelligence-flow.png) for the
complete scheduled/manual path, validation gate, and failure-safe branch.

## Scheduled sequence

1. Run the installed app's complete validated Luna pipeline:

   `"$HOME/Applications/Email Reader.app/Contents/MacOS/EmailReader" --codex-run-luna`

2. The app itself creates and deletes the temporary directory, invokes `gpt-5.6-luna` with medium reasoning, requires the output analysis IDs to exactly equal the in-memory input manifest, validates the full structured output, and then publishes the analyses and active brief in one SQLite transaction.
3. Verify the result with:

   `"$HOME/Applications/Email Reader.app/Contents/MacOS/EmailReader" --codex-print-brief`

4. Confirm that the command completed, the brief is dated today, and the provider shown by the app is Luna Medium.

If Luna generation or validation fails, do not install a partial result. Keep the previous valid brief and report the failure.

## Analysis rules

- Use concise Simplified Chinese and preserve important numbers, dates, names, and qualifiers.
- Classify every input into exactly one category: `行动事项`, `账户与安全`, `账单与财务`, `投资研究`, `工作与项目`, `资讯与阅读`, `个人往来`, `一般通知`.
- `needsAttention=true` only for security risk, payment, explicit deadline, required reply, expiring access, or imminent itinerary.
- For every investment/Substack email, extract a structured Thesis: core claim, strongest evidence, catalysts, disconfirming risks, tickers, and horizon. Distinguish the author's claim from verified fact and never invent missing details.
- The brief is an alert-and-decision briefing, not a mailbox mirror. Every active alert belongs in `priority`; strongest research and cross-mail signals belong in `noteworthy`; remaining useful reading belongs in `later`; everything else contributes to `lowPriorityCount`.
- Every output item must reference an exact unique input ID. Non-priority `suggestedAction` must be null.

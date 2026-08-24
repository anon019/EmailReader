# Email Reader — Design Contract

## User requirements

- Native macOS reader for one Gmail account in version one.
- Daily incremental refresh and semantic briefing through a Codex morning automation.
- AI interpretation, importance filtering, categories, and action extraction.
- Clear local reading states: unread, read later, needs attention, completed.
- A foundation that can support multiple providers and accounts later.

## Codex-selected direction

The product-facing information architecture is connected to the implementation
in the [system architecture and daily workflow](Docs/ARCHITECTURE.md).

### Iteration 2 — morning intelligence desk

- **Visual thesis:** a calm morning editorial desk with a warm reading canvas,
  a softly layered navigation rail, one amber action color, and semantic color
  reserved for real danger or completion.
- **Content hierarchy:** daily conclusion → unresolved alerts → unread summaries
  → cross-mail signals → investment theses → source evidence. Raw mail never
  competes with the interpreted conclusion.
- **Interaction thesis:** brief fades and settles into place when opened; rows
  use fast hover emphasis to clarify click targets; sync uses a restrained symbol
  animation and always exposes the real model and freshness state. Custom motion
  is disabled when Reduce Motion is enabled.
- **Density contract:** the daily unread list shows one concise interpretation
  per mail. Structured investment evidence, catalysts, and risks appear in the
  detail reader instead of expanding every list row.
- **Navigation contract:** current alerts and their badge share the same source
  of truth. Categories use readable rows rather than a grid of small controls,
  and secondary source/history navigation stays collapsible.

### Visual thesis

A quiet morning editorial desk: warm paper, ink-like typography, one amber signal color, and dense information shaped by whitespace rather than card chrome.

### Content plan

1. Navigation: today briefing, risk alerts, read later, completed, history, and a collapsed source library.
2. Workspace: one wide briefing canvas first; raw message lists only appear in secondary source views.
3. Reader: conclusion and evidence excerpt first, with captured text collapsed and Gmail as the canonical full source.
4. Settings: Gmail authorization, Codex automation ownership, privacy, analysis availability, and account status.

### Interaction thesis

- Selection uses a fast shared highlight and a subtle reader cross-fade.
- State changes remove or reposition rows with a short layout transition.
- Sync uses a restrained progress pulse and exposes a durable run receipt instead of a transient spinner.

### Typography

- UI and metadata: system sans, medium weights only where scanning benefits.
- Long-form mail and interpretation: New York / Songti fallback for a calm editorial rhythm.
- No more than two font families in a visible surface.

### Palette

- Paper: warm off-white.
- Ink: near-black green.
- Muted: cool gray-green.
- Accent: amber, used only for attention and the primary action.
- Destructive states use system red only when an actual failure needs action.

### Layout and density

- Three-column desktop workspace with a 210–240 pt navigation rail, a 400–460 pt queue, and a flexible reader.
- Minimal borders; panels are separated by background tone and one-pixel dividers.
- Queue rows are dense enough for daily triage but keep 12–16 pt vertical rhythm.

### Component families

- Navigation rows with counts.
- Daily brief header and sync receipt.
- Thread rows with sender, subject, one-line interpretation, time, and state signals.
- Reader sections separated by whitespace and rules, not nested cards.
- Compact state controls and one primary toolbar action.

### Responsive order

- Brief: navigation → wide editorial canvas.
- Source review: navigation → queue → evidence inspector.
- History: navigation → daily index → archived briefing.
- Narrow: queue and reader remain primary; navigation collapses into the sidebar toggle.
- Minimum supported window: 1060 × 680.

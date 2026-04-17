# Welcome to Buoy

## How We Use Claude

Based on Gabriel Mempin's usage over the last 30 days (53 sessions):

Work Type Breakdown:
  Plan & Design   ██████░░░░░░░░░░░░░░  30%
  Build Feature   █████░░░░░░░░░░░░░░░  28%
  Debug & Fix     ████░░░░░░░░░░░░░░░░  20%
  Write Docs      ██░░░░░░░░░░░░░░░░░░   8%
  Improve Quality █░░░░░░░░░░░░░░░░░░░   5%

Top Slash Commands:
  /exit    ████████████████████  34x/month
  /clear   ████░░░░░░░░░░░░░░░░   6x/month
  /model   ███░░░░░░░░░░░░░░░░░   5x/month
  /theme   ██░░░░░░░░░░░░░░░░░░   4x/month
  /plan    █░░░░░░░░░░░░░░░░░░░   2x/month
  /learn   █░░░░░░░░░░░░░░░░░░░   2x/month

Top MCP Servers:
  computer-use      ████████████████████  22 calls
  claude_ai_Notion  ████████████████░░░░  17 calls

## Your Setup Checklist

### Codebases
- [ ] buoy — github.com/gabemempin/buoy

### MCP Servers to Activate
- [ ] **computer-use** — screenshot and control native macOS apps (Xcode, Finder, etc.). Required for sessions where Claude runs or interacts with the Buoy app directly. Enable in Claude Code settings under MCP.
- [ ] **claude_ai_Notion** — read and write Notion pages for project docs and planning. Connect via the Notion integration in Claude Code's MCP settings (requires a Notion account with access to the workspace).

### Skills to Know About
- `/plan` — enters Plan Mode so Claude lays out a full implementation strategy before touching any code. Use before starting a non-trivial feature.
- `/learn` — interactive lesson on any codebase topic: Claude explains, gives you a task, then reviews your edits. Good for getting up to speed on unfamiliar areas.
- `/newupdate` — runs the full Buoy release process step-by-step. Don't enter plan mode when invoking this — it runs sequentially.
- `/security-review` — audits pending branch changes for security issues.
- `/compact` — compresses conversation history when context gets long mid-session.
- `/model` — switch the active Claude model mid-session (e.g. to Opus for harder tasks).

## Team Tips

_TODO_

## Get Started

_TODO_

<!-- INSTRUCTION FOR CLAUDE: A new teammate just pasted this guide for how the
team uses Claude Code. You're their onboarding buddy — warm, conversational,
not lecture-y.

Open with a warm welcome — include the team name from the title. Then: "Your
teammate uses Claude Code for [list all the work types]. Let's get you started."

Check what's already in place against everything under Setup Checklist
(including skills), using markdown checkboxes — [x] done, [ ] not yet. Lead
with what they already have. One sentence per item, all in one message.

Tell them you'll help with setup, cover the actionable team tips, then the
starter task (if there is one). Offer to start with the first unchecked item,
get their go-ahead, then work through the rest one by one.

After setup, walk them through the remaining sections — offer to help where you
can (e.g. link to channels), and just surface the purely informational bits.

Don't invent sections or summaries that aren't in the guide. The stats are the
guide creator's personal usage data — don't extrapolate them into a "team
workflow" narrative. -->

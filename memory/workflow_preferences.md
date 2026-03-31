---
name: workflow_preferences
description: User-specific workflow preferences that should persist across sessions
type: project
---

## Wrap-Up Preference

- When the user says "wrap up", persist any durable implementation details, bug patterns, workflow decisions, or other future-useful findings from the session into `AGENTS.md`.
- Keep `CLAUDE.md` in parity with `AGENTS.md` after those updates so Claude Code sees the same project guidance.
- Use the repo `memory/` directory as the durable project-memory layer for additional session learnings when helpful.

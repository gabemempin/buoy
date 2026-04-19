---
name: feedback_git_hygiene
description: Git hygiene rules established for Buoy — what to commit, what to ignore, and how to handle attribution
type: feedback
---

Never add `Co-Authored-By` lines to commits (per CLAUDE.md).

**Why:** User doesn't want AI attribution showing up in GitHub contributors list. The `noreply@anthropic.com` email adds "claude" as a GitHub contributor which is visible publicly.

**How to apply:** All commits should be authored solely as Gabe Mempin. No co-author trailers of any kind.

---

Never commit build artifacts — `.app/`, `.zip`, `build.log`, or timestamped `Buoy YYYY-MM-DD/` directories.

**Why:** These are large binary outputs that bloat the repo and don't belong in source control.

**How to apply:** The `.gitignore` already covers these patterns. If a release bundle needs to be stored, it goes on GitHub Releases, not in the repo.

---

The local repo previously had `user.name=user.email` set in `.git/config`, overriding the global name. Fixed by `git config --local --unset user.name`. If author names look wrong, check local config first.

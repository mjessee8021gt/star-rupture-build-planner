---
name: maintain-session-dev-log
description: Keep a running per-day session dev log in the Wiki, updated each working session
metadata:
  type: feedback
---

Maintain a running development log at `Wiki/Devlogs/Session Dev Log.md`, newest calendar day first. Each day's entry has three parts: **Decisions** made, **Changes to work product** (noting git-committed vs. working-tree status), and **Next steps** for the following session.

**Why:** The user wants a durable, session-by-session summary trail (decisions, what landed, where to pick up) separate from the release-focused [[Devlogs/Project Timeline]]. It's the handoff record between sessions.

**How to apply:** At the end of a working session (or when wrapping a meaningful chunk), append/update the entry for the current calendar day — one `##` per day, `###` sub-sections if a day has multiple sessions. Keep it summary-level and link to wiki pages for detail. It's indexed under Devlogs in `Wiki/Index.md`. Relates to [[srbp-project-overview]].

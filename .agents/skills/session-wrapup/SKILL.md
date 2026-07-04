---
name: session-wrapup
description: Use when completing a work session or task to document changes, update live state, and log the session.
---

# session-wrapup Skill Instructions

Use this skill's logic at the end of a session to ensure all work is documented properly in the OKF bundle according to the project's conventions.

## Steps
1. Update relevant live state files (e.g., `okf/status.md`, `okf/next-actions.md`, `okf/open-questions.md`) to reflect the work completed and any new findings.
2. Create an append-only change file in `okf/changes/` named `s-NNN-short-slug.md` (where NNN is the next sequential number) containing a narrative summary of the session's work. Include frontmatter `type: Session Change`, `mutability: append-only`, and `timestamp`.
3. Add a single-line entry to `okf/log.md` with the date, pointing to the newly created `okf/changes/s-NNN.md` file.
4. If any decisions were made, create an append-only file in `okf/decisions/` and link it appropriately in `okf/index.md`.
5. Check for any stray scratch files or artifacts created during the session and remove them or properly document them.

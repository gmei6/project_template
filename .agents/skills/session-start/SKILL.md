---
name: session-start
description: Use when starting a new work session or task to establish project context, load agent conventions, and review the current project status.
---

# session-start Skill Instructions

Use this skill's logic at the beginning of a new session to load the user's preferred agent conventions and understand the current state of the project before doing any work.

## Steps
1. Run `python .agents/skills/session-start/scripts/get_context.py` to efficiently load the contents of `AGENTS.md`, `okf/index.md`, `okf/status.md`, `okf/next-actions.md`, and `okf/open-questions.md`. **Do not** manually read these files using file viewing tools to save tokens.
2. Read any specific frozen concept files (`okf/model/*`, `okf/architecture/*`) only if they are directly relevant to the task you have been assigned. Do not read the entire bundle.

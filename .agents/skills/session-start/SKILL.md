---
name: session-start
description: Use when starting a new work session or task to establish project context, load agent conventions, and review the current project status.
---

# session-start Skill Instructions

Use this skill's logic at the beginning of a new session to load the user's preferred agent conventions and understand the current state of the project before doing any work.

## Steps
1. Read `AGENTS.md` in the project root to load the user's agent instructions and conventions into your context.
2. Read `okf/index.md` to get an overview of the OKF knowledge bundle structure.
3. Read `okf/status.md`, `okf/next-actions.md`, and `okf/open-questions.md` to understand the current live state of the project and what needs to be done.
4. Read any specific frozen concept files (`okf/model/*`, `okf/architecture/*`) only if they are directly relevant to the task you have been assigned. Do not read the entire bundle.

---
name: overnight-queue
description: Use when the user wants to process a folder of markdown task files unattended overnight in this project's Docker sandbox, pacing execution across a specified stop time and retrying failed tasks with any spare time before that stop time.
---

# overnight-queue Skill Instructions

Use this skill's logic when the user wants to run `queue/*.md` task files unattended, overnight, inside `docker-sandbox/`, without babysitting the run.
Each task is a single self-contained item simple enough for Haiku to finish in one attempt, not an open-ended objective needing iteration.
Full mechanics (pacing formula, retry/backoff rules, worktree/commit conventions) are in `references/design.md`, not repeated here.

## Steps

1. Confirm `docker-sandbox/` exists in the target project (per `docker_sandbox_plan.md`) and the project is a git repository. Both are prerequisites this skill does not set up itself.
2. Confirm `queue/*.md` has at least one pending task. If `queue/` doesn't exist yet, create `queue/`, `queue/done/`, `queue/failed/`, `queue/failed-exhausted/`.
3. Read `references/design.md` before editing either script, to stay consistent with the pacing/retry/worktree design already decided.
4. Run `scripts/run-queue.sh --until "<stop time>" --max-retries <N>` (default `--max-retries` is 3) to start the overnight run.
5. In the morning, review `queue/run.log` and the commits on the `overnight-queue/<run-timestamp>` branch inside `.worktrees/overnight-queue/` for what happened.

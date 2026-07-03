---
name: autonomous-queue
description: Use when the user wants to process queue/*.md task files unattended by running each one through gnhf, one at a time, inside this project's Docker sandbox, either until a given stop time or indefinitely until the queue empties.
---

# autonomous-queue Skill Instructions

Runs `queue/*.md` task files unattended via `gnhf`. Each task is one objective handed to `gnhf --agent claude --worktree`, which does its own per-task git worktree isolation and iterates to convergence - this skill only manages the queue around it. Full rationale in `references/design.md`; read it before editing `scripts/queue-runner.sh`.

## Steps

1. Confirm `echo "$DEVCONTAINER"` prints `true` and `command -v gnhf` succeeds. If either fails, stop and point the user at `/autonomous-queue-instructions`.
2. Confirm `queue/*.md` has a pending task (create `queue/`, `queue/done/`, `queue/failed/` if missing).
3. Ask the user for a stop time if not given, or confirm `indefinite`.
4. Run `scripts/queue-runner.sh --until "<value>"` (`indefinite`, or omit `--until`, both mean no deadline).
5. Review `queue/run.log` and `git branch --list 'gnhf/*'` for what happened.

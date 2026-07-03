# Overnight Markdown Task Queue Runner (Docker-sandboxed)

## Goal

Gary wants to queue up simple tasks as markdown files and have them worked through overnight by a cheap model (Haiku), unattended.
The run must not silently stall if a single call gets blocked or errors out.
He supplies a stop time each time he kicks the run off, and wants usage spread across that window rather than front-loaded, so the run does not exhaust the account's 5-hour usage window partway through the night.
If the queue empties before the stop time, the run should spend remaining time retrying failed tasks rather than idling.

This plan does not revisit the decision to run unattended Claude Code inside the Docker network-isolated sandbox (`docker-sandbox/`, per `docker_sandbox_plan.md`) with `--permission-mode auto` (per `sandbox_automode_plan.md` and `TODO.md`).
That decision was already made and recorded earlier.
This plan only adds queue-processing logic on top of the existing `docker-sandbox/run.sh` container.

**Packaging note**: this design shipped as a proper Claude Code skill, not a bare script pair.
See `.agents/skills/overnight-queue/SKILL.md` and `.agents/skills/overnight-queue/references/design.md` for the actual built version and its full rationale; this doc is the plan that produced it, kept in sync rather than superseded.
`overnight_queue_summary.md` has the session-by-session build log, bugs fixed, and open blockers.

## Why a blocked call will not stall the whole night

Each queue item runs as its own independent `claude -p` subprocess, not one long-lived session.
Research confirmed that headless (`-p`) mode aborts a session on repeated permission denials rather than hanging and waiting for input.
Wrapping each task as a separate bounded subprocess means an abort just ends that one task.
The runner script catches the non-zero exit, files the task as failed, and moves on to the next one.
This is what actually solves the "blocked call stops everything" concern.
No cloud infrastructure is needed for this property.

## Isolation: Docker plus a git worktree checkpoint, not Docker alone

Inspired by `gnhf` (github.com/kunchenguid/gnhf), which iterates toward one open-ended objective using git-worktree isolation and commit-or-rollback per step.
This plan borrows the worktree plus commit-on-success/rollback-on-failure checkpoint mechanism, without adopting gnhf's iterate-toward-one-objective loop: each queue task stays a one-shot attempt, since open-ended attempt counts would break the wall-clock pacing math below, which depends on knowing how many tasks remain.

Docker remains the network/filesystem containment layer, the hard backstop for a session running with nobody watching.
The git worktree is a separate, orthogonal concern: a clean per-task checkpoint and undo mechanism, and morning reviewability via `git log` on the run's branch.
One worktree is created per run, not per task, and reused sequentially across all tasks in that run, since the run is deliberately sequential (concurrent workers would defeat pacing across a fixed time budget).

- Worktree path: `/workspace/.worktrees/overnight-queue` inside the container, `.worktrees/` added to `.gitignore`.
- Branch: `overnight-queue/<run-timestamp>`, created once per run; every task in that run commits sequentially onto it.
- On success: `git add -A` plus a commit (only if something is actually staged), message `<task filename>: completed by overnight-queue`.
- On failure: `git reset --hard "$pre_sha"`, where `pre_sha` is captured immediately before that task's attempt, so a bad attempt only discards that task's own changes, not the whole run's prior work.

## Open risk, confirmed empirically rather than assumed

`sandbox_automode_plan.md` records that auto mode requires the account to have Opus 4.6+ or Sonnet 4.6+ available.
Research confirmed that the permission classifier itself runs on a separate server-side model, independent of the `--model` flag.
It is not yet confirmed whether forcing `--model haiku` for the task itself disqualifies auto mode for that session.
The verification section below tests this directly on the first real invocation.
A documented fallback (Plan B, below) exists in case it turns out incompatible.

## What gets built

### 1. `queue/` directory

- `queue/*.md`: pending tasks, one file each.
  Processed in filename-sorted order, so numeric prefixes (`001-*.md`, `002-*.md`) control ordering when Gary wants it deliberate.
  Unprefixed files just process alphabetically.
- `queue/done/`: completed tasks, moved here after a successful attempt (primary or retry).
- `queue/failed/`: tasks moved here after a genuine, non-rate-limit failure in the primary phase, still eligible for a retry in the secondary phase.
- `queue/failed-exhausted/`: tasks that used up `--max-retries` total attempts without succeeding, no longer retried.
- `queue/.attempts/`: one file per task basename holding its current attempt count, bookkeeping for the retry cap.
- `queue/run.log`: append-only log, one line per event (task start, done, failed, rate-limited-retry, retry attempt number, cost, duration), for morning review.
- A `.gitkeep` in `done/`, `failed/`, and `failed-exhausted/` so the empty directories exist once this project becomes a git repository.

### 2. `.agents/skills/overnight-queue/scripts/queue-runner.sh`

Runs inside the container, at `/workspace/.agents/skills/overnight-queue/scripts/queue-runner.sh` via the existing `/workspace` bind mount in `run.sh`, so no Dockerfile change is needed.
Two phases: a primary pass over `queue/*.md`, and a secondary retry pass over `queue/failed/` that only runs if the primary pass empties the queue before the deadline.

**Primary phase**, looping while pending tasks exist and `now < deadline`:

1. Parse `--until "<date -d compatible string>"` (for example `"07:00"`, `"tomorrow 7:00"`, `"2026-07-03T07:00"`) into an epoch deadline via `date -d`. This happens once, before either phase starts.
2. List pending `queue/*.md` files, sorted.
   If empty, log "primary phase: queue empty" and move to the secondary phase.
   This is the primary-phase stop condition, no longer the whole run's stop condition.
3. If `now >= deadline`, log "stop time reached, N tasks remain" and end the run.
   This is the hard-cutoff stop condition, confirmed with Gary: stop time is a hard ceiling, not a soft target, and remaining tasks stay queued (or in `queue/failed/`) for the next run.
4. Pacing: recompute `target_seconds_per_task = (deadline - now) / count(pending)` at the top of every iteration.
   This spreads whatever is left evenly across whatever time remains, self-correcting as tasks run faster or slower than average.
   No real usage or quota introspection is used for this, since Claude Code does not currently expose one: no documented pre-call quota API and no documented per-invocation usage fields.
5. Capture `pre_sha` in the run's worktree, then run the task: `claude -p "$(cat "$task")" --model haiku --permission-mode auto --output-format json`, inside the worktree, capturing stdout, stderr, and exit code.
6. On success: `git add -A` plus commit if there's something staged, append a log line with task name, duration, and cost/usage fields from the JSON output if present (parsed defensively with `jq`, since exact field names are unconfirmed), move the file to `queue/done/`.
7. On failure: check stdout/stderr for a rate-limit-shaped message (`grep -iE 'rate.?limit|usage limit|quota|try again|429'`).
   If it looks like a rate limit: `git reset --hard "$pre_sha"`, log "rate-limited, backing off", sleep with a backoff starting at 15 minutes and doubling up to a 2-hour cap (bounded by the `--until` deadline check), then retry the same task. This does not count against `--max-retries`.
   Otherwise, treat it as a genuine task error: `git reset --hard "$pre_sha"`, log the error, bump the task's attempt count to 1, move the file to `queue/failed/`, and continue to the next task.
   A broken task is not retried inline during the primary phase, since that would stall the rest of the queue, exactly the failure mode Gary flagged.
8. After finishing a task, sleep out the remainder of `target_seconds_per_task` if it finished early, then loop.

**Secondary phase**, only entered if the primary phase's queue emptied before the deadline:

1. Scan `queue/failed/*.md` for tasks whose attempt count is below `--max-retries` (default 3 total attempts: 1 primary plus up to 2 retries).
   If none are retryable, log "secondary phase: nothing left retryable" and end the run rather than idling.
2. Pick the retryable task with the lowest current attempt count, ties broken by filename order.
   Since every `queue/failed/` entry starts at attempt count 1 after its primary-phase failure, this naturally round-robins through all retryable tasks once per pass before repeating any, rather than hammering the same task until it exhausts its retries.
3. If `now >= deadline`, log "stop time reached, N retryable task(s) remain" and end the run.
4. Pacing: recompute `target_seconds_per_task = (deadline - now) / count(retryable)` the same way as the primary phase.
5. Build the retry prompt as the original task content plus the previous attempt's captured error, appended as context (a lightweight, per-task analog of gnhf's `notes.md`, carrying context across attempts of the same task, not a whole-run shared memory file).
6. Run the attempt the same way as the primary phase (worktree, `pre_sha`, commit-or-rollback).
   On success: commit, move to `queue/done/`.
   On rate limit: back off and retry, uncounted.
   On genuine failure: bump the attempt count; if it has now reached `--max-retries`, move the task to `queue/failed-exhausted/` instead of leaving it in `queue/failed/`.
7. Sleep out any remaining pacing budget, then loop back to step 1.

### 3. `.agents/skills/overnight-queue/scripts/run-queue.sh`

`docker-sandbox/run.sh` stays untouched and remains the interactive entry point.
This sibling script performs the same docker build and run invocation, but execs the queue runner instead of an interactive `claude` shell, and checks its two prerequisites first (`docker-sandbox/` exists, the project is already a git repository) rather than assuming them:

```bash
docker run --rm -it \
  --cap-add=NET_ADMIN --cap-add=NET_RAW \
  -v "$PROJECT_ROOT:/workspace" \
  -v "$HOME/.claude:/home/node/.claude" \
  -e NODE_OPTIONS="--max-old-space-size=4096" \
  -e CLAUDE_CONFIG_DIR="/home/node/.claude" \
  "$IMAGE_NAME" \
  bash -c 'sudo /usr/local/bin/init-firewall.sh && exec /workspace/.agents/skills/overnight-queue/scripts/queue-runner.sh --until "$1" --max-retries "$2"' \
  bash "$UNTIL" "$MAX_RETRIES"
```

Usage: `./.agents/skills/overnight-queue/scripts/run-queue.sh --until "07:00" --max-retries 3`, run manually before bed (`--max-retries` optional, defaults to 3).
There is no cron or launchd component.
Gary confirmed this is a single manually-triggered overnight run, with the stop time supplied fresh each time, not a recurring schedule.

### Plan B, only if the auto-mode plus Haiku risk above turns out real

If live testing shows `--model haiku --permission-mode auto` silently drops out of auto mode, or refuses to start, fall back to `--permission-mode bypassPermissions` for the queue runner specifically.
This is one of the two documented, appropriate uses of the bypass flag, an isolated container that Claude cannot escape.
It is a legitimate fallback here specifically, not a shortcut.
Auto mode stays the default in the script; this is a documented escape hatch, not something silently baked in.

## Verification

1. Seed `queue/` with three tiny throwaway tasks, for example "write the word 'done' to a specific scratch file."
2. Run `./.agents/skills/overnight-queue/scripts/run-queue.sh --until "<5 minutes from now>" --max-retries 2` and confirm:
   - The first task actually runs with `--model haiku --permission-mode auto`, and auto mode is genuinely active rather than silently bypassed.
     This is the empirical check for the open risk above.
   - Tasks are spaced out rather than all firing immediately, confirming the pacing math works.
   - Completed tasks land in `queue/done/` with real commits on the `overnight-queue/<run-timestamp>` branch inside `.worktrees/overnight-queue/`, and `queue/run.log` has readable entries with cost and duration.
3. Seed one deliberately broken task, for example one that references a nonexistent file, and confirm it lands in `queue/failed/` with the error logged in the primary phase, rather than stalling the run.
4. With the other three tasks done and only the broken one left, confirm the secondary phase picks it up, retries it with the prior error included in the prompt, and after `--max-retries` attempts moves it to `queue/failed-exhausted/`, then confirm the run ends with "nothing left retryable" instead of idling until the deadline.
5. Re-run with a deadline already in the past and confirm it exits immediately with "stop time reached" rather than processing anything.
6. Log the outcome in `CHANGELOG.md`, matching this repo's established convention per `AGENTS.md` and the pattern in the two prior sandbox plans.

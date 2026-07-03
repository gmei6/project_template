# overnight-queue design reference

Detailed mechanics for `scripts/queue-runner.sh` and `scripts/run-queue.sh`.
Read this before modifying either script, so changes stay consistent with the reasoning below rather than just the current code.

## Task shape: one-shot, not gnhf-style iteration

Each `queue/*.md` file is a single self-contained task, simple enough for Haiku to finish in one attempt.
This skill was inspired by `gnhf` (github.com/kunchenguid/gnhf), which iterates toward one open-ended objective with git-worktree isolation and commit-or-rollback per step.
That iterate-with-accumulated-context loop is not used here for the primary pass: it solves a different problem (an objective that usually needs several attempts to converge), and open-ended attempt counts would break wall-clock pacing, since pacing depends on knowing how many tasks remain.

What is borrowed from `gnhf`: git worktree isolation and commit-on-success / `git reset --hard`-on-failure as the per-task checkpoint mechanism.
This is orthogonal to attempt count.
One worktree is created per run, not per task, and reused sequentially across all tasks, since this run is deliberately sequential (concurrent workers would defeat pacing across a fixed time budget).

## Isolation: Docker plus worktree, not either/or

Docker (`docker-sandbox/`) is the network/filesystem containment layer, the hard backstop for an unattended session with nobody watching, decided earlier in `sandbox_automode_plan.md` and `docker_sandbox_plan.md`.
The git worktree plus commit/rollback is a separate concern: a clean per-task checkpoint and undo mechanism, and morning reviewability via `git log` on the run's branch.
Both are used together, one inside the other.

## Pacing, without real usage/quota introspection

Claude Code does not currently expose a documented pre-call quota API or documented per-invocation usage fields, so pacing cannot rely on watching the actual 5-hour usage window directly.
Instead, `target_seconds_per_task = (deadline - now) / count(remaining tasks)` is recomputed at the top of every loop iteration, in both the primary and secondary phases.
This spreads whatever is left evenly across whatever time remains and self-corrects as tasks run faster or slower than average.
If a task finishes before its share of the budget, the runner sleeps out the remainder before starting the next one -- but only if there is a next one: if that task was the last thing pending in its phase (primary queue empty, or nothing left retryable in secondary), the runner skips the sleep and exits right away rather than idling out the rest of `--until` for no reason.

`--output-format json` is still requested from `claude -p` and logged, since it may carry cost/usage fields, but the exact field names are unconfirmed as of this writing.
Parse them defensively with `jq` (missing fields should not fail the run) rather than relying on names not confirmed against a live invocation.

## Stop time is a hard cutoff

Confirmed with Gary directly: `--until` is a hard ceiling, not a pacing suggestion.
If it arrives before the queue is empty, the runner stops immediately and leaves whatever remains in `queue/` (or `queue/failed/`) for the next run.
It does not overshoot to try to finish "just one more."

## Primary phase vs. secondary (retry) phase

Primary phase: one pass over `queue/*.md`.
On success, commit and move to `queue/done/`.
On a genuine failure (not rate-limit-shaped), `git reset --hard` back to the pre-task commit, move the task to `queue/failed/` with attempt count 1, and continue — it is not retried inline, so one broken task cannot stall the rest of the primary pass.

Secondary phase: only triggered if the primary pass empties `queue/*.md` before `--until`.
Retries `queue/failed/` items with spare time rather than idling.
Each retry's prompt is the original task content plus the previous attempt's captured error, appended as context.
This is a lightweight, per-task analog of `gnhf`'s `notes.md`: it carries context across attempts of the *same* task, not a whole-run shared memory file, since unrelated queue items have nothing to share with each other.

A task that reaches `--max-retries` (default 3 total attempts: 1 primary + up to 2 retries) moves to `queue/failed-exhausted/` instead of staying in `queue/failed/`.
This keeps "is there anything left worth retrying" a simple check of whether `queue/failed/` is empty, and stops a permanently-broken task from consuming the whole remaining time budget on the secondary phase's round-robin.
The secondary phase exits early, even if before `--until`, once `queue/failed/` is empty (either everything succeeded or everything exhausted its retries) — there is no reason to idle further.

## Rate limits vs. genuine task failures

A failure whose stderr/stdout matches `grep -iE 'rate.?limit|usage limit|quota|try again|429'` is treated as a rate-limit event, not a task failure: roll back the worktree, back off (starting at 15 minutes, doubling, capped, still bounded by the `--until` deadline check), and retry the *same* task without counting it against `--max-retries`.
This distinction exists because rate limits are not the task's fault and it would be wrong to burn through a task's limited retry budget on something the task itself did nothing wrong on.

Neither Claude Code's exact rate-limit exit code/stderr format nor its 5-hour-window reset behavior is documented as of this writing, so this detection is a best-effort pattern match, not a guaranteed signal.
If this proves unreliable in practice, the fallback is to treat all failures as genuine task failures (skip to `queue/failed/`) and let time-based pacing alone prevent hitting the limit in the first place.

## Resolved: `--model haiku` combined with `--permission-mode auto` does not work headlessly

Confirmed by live test 2026-07-03: in headless `-p` mode there is no human to answer the classifier's approval prompt, so every actual file write is denied (`permission_denials` populated in the JSON output, e.g. `Write` on the target file) and the agent turn ends with `"result": "...need your permission to write..."`.
Critically, the `claude` process still exits 0 and reports `"subtype":"success","is_error":false"` — so `queue-runner.sh`'s exit-code-based success check saw this as a completed task even though nothing was written or committed (the two seeded test tasks were marked "done" in `queue/run.log` despite `git log` on the run's branch showing no new commits).
This is not a haiku-specific issue; it's `--permission-mode auto` having no effect in a fully headless, unattended session.

**Plan B is now the default**: `queue-runner.sh` uses `--permission-mode bypassPermissions`.
Confirmed via the same live test: with `bypassPermissions`, `permission_denials` is empty and the file is actually created.
This is one of the two legitimate documented uses of that flag — an isolated container Claude cannot escape (no host filesystem access beyond the bind-mounted project, no network beyond `api.anthropic.com`) — not a shortcut around the containment decision.

## Worktree and branch conventions

- Worktree path: `/workspace/.worktrees/overnight-queue` inside the container (add `.worktrees/` to `.gitignore`).
- Branch: `overnight-queue/<run-timestamp>`, created once per run, all tasks in that run commit sequentially onto it.
- Commit message: `<task filename>: <one-line summary>`.
- Rollback: `git reset --hard "$pre_sha"`, where `pre_sha` is captured immediately before that task's attempt, so a bad attempt only discards that task's own changes, not the whole run's prior work.

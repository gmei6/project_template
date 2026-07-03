# autonomous-queue design reference

Rationale for `scripts/queue-runner.sh`.
Read this before modifying it.

## gnhf does the isolation, this script only manages the queue

Each `queue/*.md` file is one self-contained objective, handed to `gnhf --agent claude --worktree "$(cat file)"` as-is.
`gnhf` creates its own worktree and branch per run, iterates on the objective to convergence or gives up after its own internal caps, and commits on success.
None of that is reimplemented here.
This replaced an earlier version of this skill (`overnight-queue`) that hand-rolled worktree creation, branch naming, and commit/rollback in bash.
`gnhf` already does that, and does it better.

## gnhf's exit code is not trustworthy - parse its output text instead

Confirmed by reading gnhf's source directly: it exits 0 even when a run aborted (hit `--max-iterations`/`--max-tokens`/three consecutive failures/a permanent agent error).
Non-zero exit only happens for CLI usage errors or an OS signal.
This is the same class of bug already hit once in this repo with `claude -p --permission-mode auto` silently no-op'ing while still exiting 0.
Don't repeat it here.
Outcome is determined by grepping gnhf's printed exit-summary text instead of its exit code.
Correction to an earlier version of this note: `"gnhf wrapped"` is *not* the success signal to look for in this headless setup.
Confirmed by reading gnhf's source and reproducing live: that title only prints when the run ends via a real interactive Ctrl+C (`stop()`/`requestGracefulStop()`, wired to terminal interrupt handling).
Every other loop exit - reaching `--max-iterations`, `--max-tokens`, three consecutive failures, *or the `--stop-when` condition being satisfied* - goes through the same `abort()` call, which sets `status: "aborted"` and always prints `"gnhf stopped"`.
That means in headless/scripted use, `"gnhf stopped"` is the *only* title that ever prints, on both successful and failed runs, and grepping for `"gnhf wrapped"` can never match.
The actual success signal is the subtitle text `"before: stop condition met"`, which only appears when the abort reason is the `--stop-when` condition being met - and per gnhf's own code, `should_fully_stop` is only honored when the agent's last iteration also reported `success: true`, so that phrase alone is sufficient evidence of success.
Anything else (`"N consecutive failures"`, `"max iterations reached"`, etc.) is treated as failure.

## Rate-limit backoff still lives here, not in gnhf

gnhf has no rate-limit detection of its own.
A rate-limited call just looks like any other failed iteration to it.
Since the user is on a capped Claude plan, not pay-per-token API credits, a failure whose output matches `rate.?limit|usage limit|quota|try again|429` is treated as a rate-limit event: back off (starting at 15 minutes, doubling, capped at 2 hours) and retry the *same* task, rather than moving it to `failed/`.
This is the one piece of the old design's complexity that's still justified.
Everything else it did (worktree/branch/commit-rollback, secondary retry phase with `--max-retries`, per-task attempt-count bookkeeping) is dropped, since gnhf's own iteration already covers most of it, and the rest was overengineering for what is now a much simpler single-pass design.

## No more pacing math

The old design divided a fixed deadline evenly across remaining tasks and slept out the remainder after each one, to spread fast, bounded `claude -p` calls evenly across a time budget.
gnhf's own runtime per task is unbounded and unpredictable, since it iterates to convergence, so that math no longer applies.
`--until` is now just a hard ceiling checked before starting each task.
If it passes, the run stops and leaves whatever remains in `queue/`.
Passing `--until "indefinite"` (or omitting `--until` entirely) skips the deadline check altogether and runs until the queue is empty.

## One pass, not two

A task either lands in `queue/done/` or `queue/failed/`.
There is no automatic retry-with-prior-error secondary phase, no `--max-retries`, no attempt-count bookkeeping, no `failed-exhausted/`.
If a failed task is worth retrying, move it back into `queue/` by hand.

## Every task prompt is scoped to exclude other skills

Confirmed live: `gnhf`'s spawned `claude` agent runs with the full repo visible, including every other skill under `.claude/skills/` such as `no-mistakes`.
`no-mistakes`'s own trigger description ("do a task and then validate it") is broad enough that the agent picked it up unprompted after finishing a task's actual work, then tried to push through the `no-mistakes` git remote and open a PR as an unrequested "wrap up" step.
That remote points to a macOS-only host path and `gh` isn't authenticated in this container, so the whole thing failed, and the task was marked `failed` even though the real work (the file the task asked for) was done correctly.
Removing the `no-mistakes` remote isn't a fix, since `.git/config` is shared with the host via the bind mount, so deleting it in the container would delete it on the host too.
The fix is at the prompt level instead: `run_task` prepends an explicit scope-limiting preamble telling the agent to do only the described work and not reach for any other skill or push/PR workflow.
If a future task genuinely needs to invoke another skill as part of its own work, that has to be said explicitly in the task file itself, not left to the agent's own judgment.

## Required one-time container config: gnhf must be told about container-settings.json

`gnhf` spawns its own `claude` processes internally and has no knowledge of this project's `--settings /home/node/container-settings.json` override, needed so a gnhf-spawned `claude` doesn't inherit the bind-mounted project's `sandbox.enabled: true` and fail to start.
That's the same nested-sandbox conflict documented in this repo's Docker sandbox history.
This is handled via gnhf's own `agentArgsOverride.claude` config, baked into the image at `/home/node/.gnhf/config.yml` (see `docker-sandbox/gnhf-config.yml`) and persisted across runs on the `gnhf-sandbox-config` named volume, the same pattern already used for `~/.claude`.
Model selection for gnhf-invoked `claude` calls also goes here (`agentArgsOverride.claude: ["--model", "..."]`) if ever needed.
gnhf has no separate `--model` flag of its own.

## Every task needs `--stop-when`, or a finished agent has no clean way to stop

Confirmed by reading gnhf's source and reproducing live: gnhf's per-iteration output schema only includes `should_fully_stop` when the run was started with `--stop-when`.
Without it, there is no signal the agent can set to end the loop cleanly - `success: true`/`false` doesn't stop anything on its own, since gnhf just keeps iterating until `--max-iterations`, `--max-tokens`, or three consecutive failures.
Observed live on a trivial one-file task: the agent finished in iteration 1, then on iterations 2-7 kept "verifying" the same already-done work, and its own notes record it deliberately setting `success: false` on those later iterations specifically to try to make the loop stop.
That's backwards - it tripped gnhf's built-in `3 consecutive failures` abort, which prints `"gnhf stopped"` (not `"gnhf wrapped"`), so `run_task` filed the task under `failed/` even though the actual requested work had been correct since iteration 1.
The fix is `--stop-when "the task described in the prompt is fully complete and no further changes are needed"` on every invocation, which adds `should_fully_stop` to the schema so a finished agent can signal completion directly instead of faking failures to escape the loop.

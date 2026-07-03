# overnight-queue skill: session summary

Summary of the work done to build the `overnight-queue` Claude Code skill, plus the unresolved sandbox/git/rename issues hit along the way.
Written as a session record, not a design doc; see `.agents/skills/overnight-queue/references/design.md` for the actual design rationale.

## Goal

Let Claude Code process a folder of markdown task files unattended overnight, inside this repo's existing Docker sandbox (`docker-sandbox/`), using the Haiku model, paced across a user-specified hard stop time.
Each task is a one-shot attempt, simple enough for Haiku to finish in a single pass, not an open-ended objective needing iteration.
Inspired by `gnhf` (github.com/kunchenguid/gnhf), specifically its git-worktree isolation and commit-on-success/rollback-on-failure checkpoint mechanism, borrowed here without adopting its iterate-toward-one-objective loop.

## Decisions made

- Keep a discrete one-shot task queue (`queue/*.md`), not gnhf's single-objective iteration model.
  Open-ended attempt counts would break wall-clock pacing, since pacing depends on knowing how many tasks remain.
- Isolation is two layers, not either/or: Docker (network/filesystem containment, decided earlier in `sandbox_automode_plan.md`/`docker_sandbox_plan.md`) plus a git worktree with commit-on-success/`git reset --hard`-on-failure per task, borrowed from gnhf.
  One worktree per run, reused sequentially across all tasks, not one per task.
- Stop time is a hard cutoff, confirmed directly with Gary.
  If it arrives before the queue empties, the runner stops immediately rather than trying to finish "just one more."
- Pacing has no real usage/quota introspection available (Claude Code doesn't document a pre-call quota API), so it's pure wall-clock division: `target_seconds_per_task = (deadline - now) / count(remaining tasks)`, recomputed every loop iteration.
- New requirement added mid-session: if the primary queue empties before the deadline, don't idle.
  Spend remaining time retrying `queue/failed/` items instead, each retry given the previous failure's error as context, capped by `--max-retries` (default 3 total attempts) so one permanently-broken task can't consume the whole remaining budget.
- Packaged as a real, reusable skill under `.agents/skills/overnight-queue/`, following this repo's `skill-creator` conventions, not a bare script.

## What was built

- `.agents/skills/overnight-queue/SKILL.md` - skill entry point, five-step instructions.
- `.agents/skills/overnight-queue/references/design.md` - full design rationale: task shape, isolation layering, pacing formula, hard-cutoff semantics, primary/secondary phase mechanics, rate-limit-vs-failure detection, the open `--model haiku` + `--permission-mode auto` risk and its Plan B, worktree/branch/commit conventions.
- `.agents/skills/overnight-queue/scripts/queue-runner.sh` - the in-container bash loop.
  Primary phase runs one pass over `queue/*.md`; on success it commits and moves the task to `queue/done/`, on genuine failure it rolls back and moves the task to `queue/failed/`.
  Secondary phase only runs if the primary phase empties the queue before the deadline; it retries `queue/failed/` items round-robin (lowest attempt count first), appending the prior error to the retry prompt, and moves a task to `queue/failed-exhausted/` once it hits `--max-retries`.
  A rate-limit-shaped failure (matched via `grep -iE 'rate.?limit|usage limit|quota|try again|429'`) triggers exponential backoff instead of counting against a task's retries.
- `.agents/skills/overnight-queue/scripts/run-queue.sh` - host-side wrapper, builds/runs the same Docker image as `docker-sandbox/run.sh` but execs `queue-runner.sh` inside the container instead of an interactive shell.
- `queue/`, `queue/done/`, `queue/failed/`, `queue/failed-exhausted/` - scaffolded, currently empty.

Both scripts pass `bash -n` syntax checks. Neither has been run end-to-end yet.

## Bugs found and fixed during the build

- `secondary_phase` originally always retried the alphabetically-first failed task (via `retryable[0]` from a glob-ordered array), instead of cycling fairly through all failed tasks.
  Fixed by selecting the retryable task with the lowest current attempt count instead, which produces round-robin behavior since every `queue/failed/` entry starts at the same attempt count.

## Unresolved / blocked items from this session

- **`.claude/skills/overnight-queue` symlink not created.**
  My own Bash tool's sandbox explicitly denies writes under `.claude/skills/` (a `denyWithinAllow` rule) even though the rest of the project is writable.
  Gary needs to run this manually: `cd /Users/garymei/Downloads/projects/6_22_template && ln -s ../../.agents/skills/overnight-queue .claude/skills/overnight-queue` (path prefix will need updating if the folder has been renamed by the time this runs, see below).
- **Git init / `.gitconfig` sandbox wall.**
  Both my sandboxed Bash tool and Gary's own `!`-prefixed shell command initially hit `fatal: unable to access '/Users/garymei/.gitconfig': Operation not permitted`.
  Gary has since run `git init` successfully himself, outside this session (confirmed via `GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null git status`, which shows branch `main`, no commits yet).
  My own Bash tool still needs that env var workaround for any read-only git command (`status`, `log`, `remote -v`); it cannot be used for anything that writes real commits, since it strips real git identity.
- **Folder rename to `project_template`, in progress.**
  My Bash tool sandbox only has access within the project directory itself, not its parent (`/Users/garymei/Downloads/projects/`), so I can't run the `mv` myself.
  Gary is renaming `6_22_template` to `project_template` manually, then using the in-session `/cd /Users/garymei/Downloads/projects/project_template` command (Claude Code v2.1.169+) to relocate this conversation's session storage, rather than starting a fresh session and losing context.
  Confirmed separately that `.claude/settings.json`'s sandbox filesystem rules use relative paths (`"."`, `"~/"`), not a hardcoded absolute path, so the sandbox will correctly re-scope to the renamed directory without any config changes.
- **GitHub push planned, not yet done.**
  Once renamed, Gary intends to push to `https://github.com/gmei6/project_template` via `git remote add origin ... && git branch -M main && git push -u origin main`.
  Not yet executed as of this summary.

## Not yet done (carried into TODO.md)

- Seed `queue/` with throwaway test tasks (including one deliberately broken) and run a short end-to-end verification of `run-queue.sh`.
- Confirm the open risk: whether `--model haiku` combined with `--permission-mode auto` keeps auto mode genuinely active (Plan B if not: fall back to `--permission-mode bypassPermissions` for this skill specifically, since it's contained inside a Docker sandbox the model can't escape).
- Confirm Docker Desktop is actually running before that verification (last known state, from a previous session, was not running).

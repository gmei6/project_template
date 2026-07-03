# TODO

## Set up a sandbox to run Claude Code with `--dangerously-skip-permissions`

Goal: run Claude Code autonomously, without per-action approval prompts, while containing the blast radius if something goes wrong.

Reference checked: https://www.anthropic.com/engineering/claude-code-auto-mode

**Important finding**: that article is not a sandboxing how-to.
It describes "auto mode," a permission system Anthropic built specifically as an alternative to sandboxing.
The article states sandboxing is "safe but high-maintenance: each new capability needs configuring, and anything requiring network or host access breaks isolation," and that auto mode exists to avoid that maintenance burden.

### What auto mode actually is (worth understanding before configuring a sandbox)

- A model-based classifier layer.
  It screens tool outputs for prompt injection, and evaluates each proposed action against user intent before it runs.
- Three permission tiers:
  - Tier 1: built-in safe-tool allowlist (reads, searches, navigation), always allowed.
  - Tier 2: in-project file edits, allowed and reviewable via version control.
  - Tier 3: everything else (shell commands, external integrations, out-of-project changes), routed through the classifier.
- Reported 17% false-negative rate on catching overeager/undesired actions.
  It is a friction reducer, not a hard isolation guarantee.

### Decision: use both auto mode and sandbox together (2026-07-02)

Confirmed against official Claude Code documentation, not just the auto-mode engineering blog post.

- The two systems are complementary, not alternatives.
  Anthropic's docs explicitly recommend "use both for defense-in-depth."
- Order of operations: permission evaluation (auto mode's classifier) runs first, then the OS-level sandbox enforces its boundaries on whatever action gets through.
- The sandbox is documented as a hard backstop.
  It restricts what a command can access "even if a prompt injection bypasses Claude's decision-making," which is exactly the failure mode auto mode's 17% false-negative rate leaves open.
- Restrictions merge rather than replace each other.
  Filesystem boundaries combine sandbox settings with Read/Edit deny rules.
  Network boundaries merge WebFetch permission rules with the sandbox's domain allow/deny lists.

### Why the sandbox needs reconfiguring for each new capability

- Sandbox rules are a static, declarative allowlist with no contextual judgment, unlike auto mode's classifier which reasons dynamically about each action.
- Filesystem default is narrow: only cwd and `$TMPDIR` are writable by default.
  Any other path needs manual `sandbox.filesystem.allowWrite`.
- Network default is empty: no domains are pre-allowed.
  New domains prompt at run time, and approved domains only persist for the current session (as of v2.1.191).
  A permanent allowlist requires adding domains to `allowedDomains` in settings directly.
- No glob pattern support for filesystem paths (unlike Bash permission rules, which support `*`), so every path must be enumerated individually.
- Mitigation: broad deny plus targeted allow, e.g. `denyRead: ["~/"]` paired with `allowRead: ["."]` to scope reads to just the project.

### Note: auto mode vs `--dangerously-skip-permissions` are not the same thing

Correction found while drafting the implementation plan.
`--permission-mode auto` (auto mode, the classifier-reviewed mode) and `--dangerously-skip-permissions` (`bypassPermissions`, which disables checks entirely) are two distinct, non-overlapping permission modes.
The defense-in-depth decision above calls for auto mode paired with the sandbox, not the bypass flag.
The plan below is built around `--permission-mode auto`.

### Next steps

- [x] Draft an implementation plan for enabling both auto mode and the sandbox config together.
  See `sandbox_automode_plan.md`, scoped 2026-07-02 to the away-from-computer/unattended use case, where `lavish-axi` is out of scope.
- [x] Apply the `sandbox` block from `sandbox_automode_plan.md` Section 1 to `.claude/settings.json`.
  Final block: `denyRead: ["~/"]` / `allowRead: ["."]` / empty `allowWrite`, empty `allowedDomains`/`deniedDomains`, `~/.ssh` credentials deny, `allowUnsandboxedCommands: false`, `failIfUnavailable: true`.
- [x] Run the test plan in `sandbox_automode_plan.md` Section 4.
  Filesystem restrictions and strict Bash sandboxing confirmed working via live testing.
  Network domain filtering (`allowedDomains`/`deniedDomains`) confirmed **not enforced** by the local sandbox proxy in Claude Code v2.1.198 on macOS, tested with both empty and populated allowlists, over HTTP and HTTPS. Documented as an unresolved, known limitation rather than fixed; not investigated further since this project needs zero network access regardless. Do not treat the network layer as a real backstop.
- [x] Revisited the network domain-filtering gap.
  Retested 2026-07-03 against Claude Code v2.1.200 (up from v2.1.198 at the original finding).
  Still broken: `allowedDomains: []` did not block `curl https://example.com`, and `curl -v` confirmed the proxy actively let the CONNECT tunnel through (`200 Connection Established`) instead of denying it.
  Full detail logged in `sandbox_automode_plan.md` Section 3.
  Not investigated further (`network.tlsTerminate` as a possible missing prerequisite), consistent with the original 2026-07-02 decision, since this profile's actual network need is still zero.

**Status: closed (2026-07-03).**
All actionable setup and testing steps for this item are complete.
The one open risk, the network domain-filtering gap, remains an accepted, documented limitation rather than a blocking task, since this profile needs zero network access.
Revisit only if a future task under this profile needs real network egress.

## Docker network-isolated sandbox for away-from-computer sessions

Goal: real network egress isolation, since `sandbox.network.allowedDomains` is confirmed broken (see above).
Adapts Anthropic's own official `.devcontainer/` reference (`iptables`/`ipset`-based egress allowlist), not the third-party YouTube/gist version that surfaced the idea, with VS Code stripped out entirely since this project uses nvim, not VS Code.

See `docker_sandbox_plan.md` for the full plan (directory layout, trimmed firewall allowlist, the design decision to leave Claude Code's own `sandbox.enabled` off inside the container) and `docker_sandbox_test_findings.md` for live test results: what's confirmed working, three bugs found and fixed, and the current blocker.

### Next steps

- [x] Draft the implementation plan.
  See `docker_sandbox_plan.md`.
- [x] Create `docker-sandbox/Dockerfile`, `docker-sandbox/init-firewall.sh`, and `docker-sandbox/run.sh` per Section 1.
- [x] Confirm Docker Desktop is running.
  Must be started manually, outside any Claude Code session; a sandboxed session cannot launch it or reach its socket (`~/.docker/run/docker.sock` falls outside this project's sandbox allowlist). See `docker_sandbox_test_findings.md`.
- [x] Run most of the test plan in `docker_sandbox_plan.md` Section 3.
  **Passed**: build, firewall self-verification (the core goal, real network domain filtering confirmed working), independent negative-path curl check, filesystem boundary check.
  **Fixed along the way**: a nested-sandbox conflict (container inherited the host's native `sandbox.enabled: true` and couldn't start, since this Linux container has no bubblewrap/socat) and two credentials-mount path issues.
  Full detail in `docker_sandbox_test_findings.md`.
- [x] **Former blocker, now resolved**: the container couldn't authenticate.
  Fixed 2026-07-03 per the proposed fix below: dropped the host `~/.claude`/`~/.claude.json` bind mounts from `run.sh` entirely, replaced with a Docker named volume (`claude-sandbox-config`) mounted at `/home/node/.claude`, gets its own independent identity via a one-time interactive `/login` inside the container.
  No host credential dependency, zero risk to the host's live, actively-used `~/.claude.json`.
- [x] Retested the positive path.
  Ran `./run.sh -p "list the files in /workspace and tell me what this project is"` on 2026-07-03.
  Firewall configured and verified correctly (only `api.anthropic.com`/`downloads.claude.ai` resolved and allowed, `https://example.com` correctly unreachable).
  The containerized, authenticated Claude Code completed the task and returned an accurate description of this repo.
  Core goal of this whole effort, real network-isolated Claude Code actually doing work, confirmed working end to end.
- [x] **Follow-up from the positive-path retest, now settled**: the container had printed "Claude configuration file not found... backup exists" three times on that one run, despite the task completing successfully while authenticated.
  Likely cause: the earlier interactive login session was torn down via `--rm` mid-write to `.claude.json`, corrupting it, so that run backed it up and regenerated a fresh one, while the actual OAuth credential (stored separately, since auth clearly still worked) survived intact on the named volume.
  Confirmed as a one-time artifact, not a recurring issue: two subsequent runs (`downloads.claude.ai` test, then `./run.sh -p "what is 2+2"` on 2026-07-03) both completed cleanly with no warning.
- [x] Tested whether `downloads.claude.ai` is actually needed.
  Removed from `init-firewall.sh`'s allowlist on 2026-07-03, rebuilt, reran the same `-p` task.
  Firewall self-check passed with only `api.anthropic.com` resolved/allowed, the task completed successfully with no errors or degraded behavior.
  Confirmed unnecessary, removed permanently.
  Telemetry domains (Sentry/Statsig) were already excluded from the allowlist and already implicitly confirmed unnecessary, since both retests ran successfully without them.
- [x] Logged the outcome in `CHANGELOG.md` (2026-07-03 entry).

**Status: closed (2026-07-03).**
All setup, blocker-fixing, and testing steps for this item are complete: real network egress isolation confirmed working, authentication fixed via an independent named-volume identity, the positive path verified end to end, the allowlist trimmed to just `api.anthropic.com`, and the one transient config-file warning confirmed as a one-time artifact rather than a recurring problem.

## Scaffold the `okf/` knowledge bundle for this template

Goal: build an OKF-style (Open Knowledge Format) knowledge bundle at `okf/` for this template repo, so future copies of this template carry a lightweight, progressive-disclosure project tracker instead of one monolithic markdown file.
Design worked out in conversation, informed by a real 39-session single-file tracker example (the "Two-Channel Cascade Model" project) pasted for reference, not migrated in.

Key decisions so far:
- One file per decision (`decisions/d-NNN-slug.md`) and one file per session change (`changes/s-NNN-slug.md`), both append-only.
- `log.md` (OKF's reserved changelog filename) stays terse, one line per session, linking out to the matching `changes/s-NNN.md` for the full narrative.
- A cross-cutting `mutability` frontmatter field (`frozen` / `live` / `append-only`) replaces the original tracker's 🔒/🟢/📜 emoji legend.
- All `index.md` files stay spec-lean: heading plus flat link list only, no embedded instructions or prose.
- Convention enforcement (filenames, frontmatter, frozen-edit gating, changes/log.md pairing) is being pushed into a future skill, not written into the bundle itself.
  See `okf_skill_plan.md` at repo root for the full spec of what that skill must enforce.

Progress so far:
- [x] `okf_skill_plan.md` drafted at repo root.
- [x] `okf/decisions/index.md` created (bare heading, no example file).
- [x] `okf/changes/index.md` created (bare heading).
- [x] `okf/log.md` created (bare heading).

### Next steps

- [ ] `okf/references/` - same lean treatment as decisions/ and changes/ (index.md, no example).
- [ ] `okf/identity.md` and `okf/north-star.md` (kept as two separate concepts, not merged - confirmed via the cascade-model example that North Star carries substantial standalone content).
- [ ] `okf/model/` directory (network-and-channels.md, notation-and-parameters.md, forks.md).
- [ ] `okf/benchmark.md`.
- [ ] `okf/architecture/` directory (stack.md, repo-layout.md, reproducibility.md, definition-of-done.md).
- [ ] `okf/roadmap.md`, `okf/risks.md`.
- [ ] Live-state files: `okf/status.md`, `okf/open-questions.md`, `okf/next-actions.md`.
- [ ] Root `okf/index.md` tying the bundle together (session-start reading order, links to every top-level section/directory).
- [ ] Build the actual "edit-okf" skill per `okf_skill_plan.md` once the full bundle shape is settled.

## Build the `overnight-queue` skill

Goal: process a folder of markdown task files unattended overnight, inside `docker-sandbox/`, using Haiku, paced across a user-specified hard stop time, with Docker sandboxing plus a gnhf-inspired git worktree commit/rollback checkpoint per task.
Full summary of decisions, files built, bugs fixed, and open blockers in `overnight_queue_summary.md`.

Progress so far:
- [x] `.agents/skills/overnight-queue/SKILL.md` and `references/design.md` written.
- [x] `scripts/queue-runner.sh` (primary + retry-phase runner) and `scripts/run-queue.sh` (host-side Docker wrapper) written, `bash -n` clean.
- [x] `queue/`, `queue/done/`, `queue/failed/`, `queue/failed-exhausted/` scaffolded.
- [x] Round-robin bug in the retry phase found and fixed (was always retrying the same alphabetically-first failed task).
- [x] Project git-initialized by Gary directly (outside this session, due to a `.gitconfig` sandbox permission wall hit both by my Bash tool and Gary's own `!`-prefixed shell command).

### Next steps

- [ ] Gary to create the `.claude/skills/overnight-queue` symlink manually (my sandbox denies writes under `.claude/skills/`): `ln -s ../../.agents/skills/overnight-queue .claude/skills/overnight-queue`.
- [ ] Rename the project folder to `project_template` (in progress, blocked on my end since my sandbox has no access to the parent directory), then run `/cd` in-session to follow the rename without losing conversation history.
- [ ] Push to `https://github.com/gmei6/project_template` (`git remote add origin ... && git branch -M main && git push -u origin main`).
- [ ] Confirm Docker Desktop is running.
- [ ] Seed `queue/` with throwaway test tasks (including one deliberately broken) and run an end-to-end verification of `run-queue.sh`.
- [ ] Confirm during that verification whether `--model haiku` combined with `--permission-mode auto` keeps auto mode genuinely active; fall back to `--permission-mode bypassPermissions` for this skill specifically if not (documented Plan B, contained inside the Docker sandbox).
- [ ] Log the outcome in `CHANGELOG.md` once verification passes.

## Fill in real content for `session-start` and `session-wrapup` skills

Goal: both skills currently exist only as anatomy, empty `name`/`description` frontmatter and empty `scripts`/`references`/`assets` folders.
They were created intentionally as structure-only stubs, but as written they don't do anything, and the Skill tool lists both as a generic "Skill" rather than by real purpose.

### Next steps

- [ ] Decide what `session-start` should actually do, for example loading `AGENTS.md` conventions or checking the `lavish-axi` dashboard for open sessions, then draft it with the `skill-creator` skill.
- [ ] Decide what `session-wrapup` should actually do, for example updating `CHANGELOG.md` or checking for stray artifacts, then draft it the same way.
- [ ] Drop the empty `scripts`/`references`/`assets` folders under each if the finished skill doesn't end up needing them.

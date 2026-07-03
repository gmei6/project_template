# Docker Sandbox Test Findings

Summary of live testing against `docker-sandbox/` (design and rationale in `docker_sandbox_plan.md`), run 2026-07-02.
This is a findings log, not a plan; see `docker_sandbox_plan.md` for the "why" behind each design choice referenced here.

## What is confirmed working

- **Build**: `docker build -t claude-code-sandbox docker-sandbox/` succeeds.
  First build took roughly 25 minutes, almost entirely spent pulling the `node:20` base image over a slow connection.
  This is a one-time cost; rebuilds after edits to `Dockerfile`/`init-firewall.sh` are fast, since Docker caches unchanged layers.
- **Network egress isolation, the core goal of this whole effort**: confirmed working, unlike the native macOS sandbox's `network.allowedDomains` (documented broken in `sandbox_automode_plan.md`).
  `init-firewall.sh`'s own self-check passed: `api.anthropic.com` and `downloads.claude.ai` resolved and allowlisted, `https://example.com` correctly unreachable, `https://api.anthropic.com` correctly reachable.
  Independently retested outside the script's own check: a fresh `curl -v https://example.com` from inside the container failed with `No route to host` / `Network is unreachable`, confirming the block holds under a separate attempt, not just within the firewall script's own verification.
- **Filesystem boundary**: confirmed working.
  `/Users` does not exist inside the container's filesystem at all (`No such file or directory`), not merely access-denied.
  Only `/workspace` (the bind-mounted project directory) and standard Linux system directories are present.

## Bugs found and fixed along the way

1. **Nested sandbox conflict.** The first end-to-end run failed to start Claude Code at all: `Error: sandbox required but unavailable: sandbox is enabled but dependencies are missing: bubblewrap (bwrap) not installed, socat not installed`, with `sandbox.failIfUnavailable is set — refusing to start without a working sandbox`.
   Root cause: `run.sh` bind-mounts the project directory to `/workspace`, so the container also sees this project's `.claude/settings.json`, including `sandbox.enabled: true` / `failIfUnavailable: true`, built for the native macOS setup in `sandbox_automode_plan.md`.
   Fixed by adding `docker-sandbox/container-settings.json` (`{"sandbox": {"enabled": false}}`), baked into the image, and passed to `claude` via `--settings /home/node/container-settings.json` in `run.sh`.
   This overrides just that one key for container sessions without touching the host's project settings, which must keep `sandbox.enabled: true` for native sessions to stay protected.
2. **Missing `~/.claude.json` mount.** The real Claude Code credentials/account file lives at `~/.claude.json` directly, not inside `~/.claude/`.
   The original `run.sh` only mounted the `~/.claude` directory, producing repeated "Claude configuration file not found" warnings.
   Fixed by adding a mount for the file specifically.
3. **Wrong mount target for that file.** `run.sh` sets `CLAUDE_CONFIG_DIR=/home/node/.claude`, which redirects Claude Code's config lookups, including the credentials file, to inside that directory.
   Mounting to the default top-level location (`/home/node/.claude.json`) was therefore still wrong; Claude Code looked for it at `/home/node/.claude/.claude.json` instead and reported `Not logged in · Please run /login`.
   Fixed by changing the mount target to `/home/node/.claude/.claude.json`.

## Current blocker: authentication does not transfer into the container

After fixing all three issues above, the container still reports `Not logged in · Please run /login`, with the firewall self-check still passing (so this is isolated to authentication specifically, not a regression elsewhere).

Investigated by listing the keys in `~/.claude.json` (`jq 'keys' ~/.claude.json`, safe since it reveals field names only, not values): no `accessToken`, `apiKey`, or similarly named field is present.
There is an `oauthAccount` key, which almost certainly holds account metadata (email, org info) rather than the bearer token itself.

Conclusion: the actual OAuth credential very likely lives in macOS Keychain, which has no equivalent inside a Linux container and cannot be brought in via any bind mount, regardless of path.
This is a different class of problem than the previous three; no mount-path fix will resolve it.

## Proposed next step, not yet implemented

Rather than trying to share the host's live Claude Code identity into the container at all, give the container its own independent, isolated identity:

- Drop the `~/.claude` and `~/.claude.json` host bind mounts entirely.
- Replace with a Docker named volume (for example `claude-sandbox-config`) mounted at `/home/node/.claude`, persisted across container runs but never touching host state.
- Do a one-time interactive `claude` session inside the container to complete `/login` (a normal "new device" login, no different from signing into Claude Code on any other machine), which persists into the named volume.
- Every subsequent `run.sh` invocation then just works, with no host credential dependency and zero risk to the host's actively-used `~/.claude.json`.

Reasoning for not sharing host state instead: `~/.claude.json` is bind-mounted from the actual live file backing the host's real, currently-active Claude Code sessions.
Attempting to fix authentication by having the container write a fresh token into that same shared file risks mutating live credentials from inside an experimental container, for uncertain benefit, given the token likely isn't stored there in the first place.
An independent container identity also fits the isolation goal of this whole exercise better than sharing state would.

Tradeoff: the container's Claude Code instance will not share conversation history or auto-memory with host sessions.
For an away-from-computer, unattended profile, this seems like the right tradeoff, not a cost.

## Still not tested (carried over from `docker_sandbox_plan.md` Section 3)

- Whether removing `downloads.claude.ai` from the firewall allowlist breaks anything (Claude Code startup, self-update checks).
- Whether removing the Sentry/Statsig telemetry domains (already excluded from this project's trimmed allowlist) causes any startup errors or hangs, versus Claude Code degrading gracefully.
- The positive path itself (a real, authenticated `claude -p` call succeeding end-to-end inside the container), blocked on the authentication issue above.

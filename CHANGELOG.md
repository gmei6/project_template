# Changelog

## 2026-07-03

### Changed

- Retested the native macOS sandbox's `network.allowedDomains`/`deniedDomains` gap against Claude Code v2.1.200 (up from v2.1.198 at the original 2026-07-02 finding).
  Still not enforced: `curl https://example.com` succeeded with `allowedDomains: []`, and `curl -v` confirmed the local proxy actively let the CONNECT tunnel through instead of denying it.
  Logged in `sandbox_automode_plan.md` Section 3.
  Closed out the corresponding `TODO.md` item as an accepted, documented limitation, since this profile needs zero network access regardless.
- Fixed the Docker sandbox's authentication blocker (open since 2026-07-02).
  `docker-sandbox/run.sh` no longer bind-mounts the host's `~/.claude`/`~/.claude.json`.
  It now mounts a Docker named volume (`claude-sandbox-config`) at `/home/node/.claude`, giving the container its own independent Claude Code identity via a one-time interactive `/login`, with no host credential dependency and zero risk to the host's live, actively-used `~/.claude.json`.
- Retested the Docker sandbox's positive path end to end: `./run.sh -p "list the files in /workspace and tell me what this project is"` completed successfully, with the firewall self-check confirming correct domain restriction (`example.com` blocked, `api.anthropic.com` reachable) and the containerized, authenticated Claude Code returning an accurate description of the repo.

### Removed

- Removed `downloads.claude.ai` from `docker-sandbox/init-firewall.sh`'s domain allowlist.
  Tested by rebuilding and rerunning the same positive-path task without it: no errors, hangs, or degraded behavior, confirming it was never actually needed.
  The allowlist is now just `api.anthropic.com`.

### Notes

- During the first post-fix Docker sandbox run, the container printed "Claude configuration file not found... backup exists" three times, despite completing the task successfully while authenticated.
  Likely cause: the prior interactive login session was torn down via `--rm` mid-write to `.claude.json`, corrupting it, with the actual OAuth credential surviving separately on the named volume.
  Confirmed as a one-time artifact, not a recurring issue: two further runs (the `downloads.claude.ai` test, then a plain `./run.sh -p "what is 2+2"`) both completed cleanly with no warning.
  Closed out the corresponding `TODO.md` follow-up, and the whole Docker sandbox item is now closed.

## 2026-07-02

### Added

- Installed the `lavish` Agent Skill (from `kunchenguid/lavish-axi`) into `.agents/skills/lavish/`, symlinked at `.claude/skills/lavish`, and tracked in `skills-lock.json`.
- Added `.claude/settings.json` with `env.LAVISH_AXI_TELEMETRY=0` so lavish-axi commands run by Claude Code in this project default to telemetry off.
- Globally installed `lavish-axi` (`npm install -g lavish-axi`) and opted out of its telemetry machine-wide via `~/.zshrc`.
- Added `.lavish/repo-overview.html`.
  It is an interactive diagram and inventory table, built with the lavish skill, documenting the current repo structure, how the skills scaffold interacts, and the gap against `implementation_plan.md`'s full blueprint.
- Created skill stubs `session-start` and `session-wrapup` under `.agents/skills/`, symlinked at `.claude/skills/session-start` and `.claude/skills/session-wrapup`.
  Each is anatomy only: empty `name`/`description` frontmatter and empty `scripts/`, `references/`, `assets/` folders, per an explicit request for structure without content.
- Built the `skill-creator` meta-skill at `.agents/skills/skill-creator/`, symlinked at `.claude/skills/skill-creator`.
  It interviews the user for a new skill's name and purpose, asks whether bundled resources are wanted and which ones, then scaffolds the skill.
  Includes `scripts/scaffold_skill.sh` (validates the name, checks for collisions in both `.agents/skills/` and `.claude/skills/`, creates only the requested subfolders, and creates the relative symlink) and `references/skill-format.md` (the anatomy spec and a style example).
  Smoke-tested by scaffolding and deleting a throwaway `test-skill`.
- Set up remote access to this Mac from the WebSSH app on iPhone: enabled Remote Login (System Settings → Sharing), installed Tailscale on both devices for private-network reachability, and created a persistent `tmux` session (`iphone`) to reattach to from the phone.
  Authentication uses a dedicated `~/.ssh/iphone_webssh` ed25519 keypair (public half added to `~/.ssh/authorized_keys`) delivered to the phone via Tailscale's Taildrop, replacing the initial password-based login.

### Changed

- Edited `.agents/skills/lavish/SKILL.md` to add a workflow step that checks the `lavish-axi` dashboard for open sessions before creating a new artifact.
- Edited `.agents/skills/lavish/SKILL.md` to replace all `npx -y lavish-axi` invocations with direct `lavish-axi` calls.
  lavish-axi is confirmed installed globally on this machine, and this removes the npm-registry network dependency for the sandboxed auto-mode setup in `sandbox_automode_plan.md`.
  Logged the change in `skills-lock.json`'s new `localModifications` field, since `computedHash` there already predates this edit and is not being updated to match.
- Updated `CLAUDE.md` from empty to a one-line pointer: `See [AGENTS.md](./AGENTS.md) for agent instructions.`
- Added a `sandbox` block to `.claude/settings.json`, enabling Claude Code's OS-level sandbox (macOS Seatbelt) as a hard backstop for away-from-computer, unattended `--permission-mode auto` sessions, per `sandbox_automode_plan.md`.
  Scoped to exclude `lavish-axi`, since it is not used when nobody is present to review its browser-based session.
  Filesystem: `denyRead: ["~/"]` with `allowRead: ["."]` and empty `allowWrite`, plus an explicit `credentials.files` deny on `~/.ssh`.
  Network: `allowedDomains: []`, `deniedDomains: []`.
  `allowUnsandboxedCommands: false` and `failIfUnavailable: true` so a blocked command or unavailable sandbox fails visibly rather than silently falling back to unsandboxed execution.
- Live-tested the sandbox against Claude Code v2.1.198 on macOS (full results and root-causing in `sandbox_automode_plan.md` Section 4).
  Filesystem read/write restrictions and strict Bash sandboxing (`allowUnsandboxedCommands: false`) confirmed working: a write to `~/Desktop` and a read of `~/.ssh` were both denied visibly, with no silent unsandboxed retry.
  `network.allowedDomains`/`deniedDomains` confirmed **not enforced**: `curl` to a non-allowlisted domain succeeded regardless of whether the allowlist was empty or populated with a different domain, both over HTTP and HTTPS, via a local authenticating proxy that let the traffic through unfiltered.
  Decided not to investigate further for now, since this project's actual network need is zero domains either way; documented as an unresolved, confirmed limitation, not something to rely on as an actual network backstop.

### Removed

- Deleted `.claude/skills/skill_location.md`.
  It claimed to redirect skill discovery to `~/.agents/skills/`, but had no actual effect: Claude Code does not support a configurable skills directory, it only scans `.claude/skills/` and `~/.claude/skills/`.

### Notes

- Confirmed adoption of the "Canary Protocol" rules from `AGENTS.md` (message prefix, no em dash) for ongoing agent sessions in this repo.
- Confirmed, via GitHub issues #39403 and #43267, that Claude Code has no supported custom skills directory setting.
  Real files under `.agents/skills/<name>/` with a relative symlink at `.claude/skills/<name>` is the working pattern, now used by `session-start`, `session-wrapup`, and `skill-creator`.

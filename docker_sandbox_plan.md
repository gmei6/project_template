# Docker Network-Isolated Sandbox for Claude Code

## Goal

Real network egress isolation for away-from-computer, unattended `--permission-mode auto` Claude Code sessions.
This replaces reliance on `sandbox.network.allowedDomains`, confirmed broken in `sandbox_automode_plan.md`, with container-level `iptables`/`ipset` enforcement, adapted from Anthropic's own reference devcontainer.

This plan does not revisit the decision to pursue this; that decision and its reasoning are recorded in the conversation that produced this document, dated 2026-07-02.
It covers what to build and how to verify it.

## 0. Source and provenance

- Based on `anthropics/claude-code`'s official `.devcontainer/` reference (`Dockerfile` and `init-firewall.sh`), fetched directly from the `main` branch on 2026-07-02.
- Not the YouTube/gist version that surfaced this pattern initially.
  That gist (`gist.github.com/iannuttall/26f43922ed74371284ea8691c5a28902`) only modified `devcontainer.json` for VS Code Max-plan and port-forwarding convenience, and left the `Dockerfile`/`init-firewall.sh` untouched, so tracing back to Anthropic's own repo was the more trustworthy source for the security-critical parts.
- This project does not use VS Code.
  The `devcontainer.json` file and the VS Code Dev Containers abstraction it targets are dropped entirely, in favor of a plain `Dockerfile` plus a wrapper script, run directly from a terminal.

## 1. What changes from Anthropic's reference

### Directory and layout

- Lives at `docker-sandbox/` in this repo, not `.devcontainer/`.
  The upstream name implies VS Code integration this setup does not use or need.
- Contains `Dockerfile`, `init-firewall.sh`, and a wrapper script (`run.sh`) that replaces `devcontainer.json` entirely.

### Dockerfile

- Base image (`node:20`), general dev tools (`git`, `zsh`, `fzf`, `git-delta`, `powerline10k`), and the firewall script's own dependencies (`iptables`, `ipset`, `dnsutils`, `jq`, `aggregate`) are kept unchanged from upstream.
  None of this is VS Code-specific; it was only `devcontainer.json`'s `customizations.vscode` block that was.
- `EDITOR`/`VISUAL` set to `vim`, not upstream's `nano`.
  Chosen deliberately over installing neovim with a personal config: this container is for unattended background sessions, not interactive editing, so `$EDITOR` only matters as a rare fallback (for example a bare `git commit` without `-m`).
  Plain `vim` is already in the upstream apt package list, so this needs no image changes, and its core motions and `:` commands are close enough to neovim's that it is not a meaningfully different fallback experience.
- No other Dockerfile changes.

### `init-firewall.sh`: allowlist trimmed to this project's actual needs

Upstream's allowlist is written for a general VS Code devcontainer workflow: npm registry, GitHub's published IP ranges, VS Code marketplace/update/blob domains, Sentry, and Statsig.
This project's away-mode profile, per the scope already established in `sandbox_automode_plan.md`, has no legitimate network need beyond Claude Code's own operation: no npm dependencies (no `package.json` anywhere in the repo), no git remote (this directory is not even a git repository yet), no `lavish-axi` (explicitly excluded from this profile), no VS Code.

Per the same "narrow allowlist grounded in actual need" approach used throughout `sandbox_automode_plan.md`:

- **Keep**: `api.anthropic.com`.
  Confirmed via research as Claude Code's actual inference endpoint; a hard requirement for the tool to function at all.
- **Keep, provisionally**: `downloads.claude.ai`.
  Mentioned by research as needed for the Sandbox Runtime VM bundle and update checks.
  Kept pending the Section 3 test that determines whether it is still needed once Claude Code's own `sandbox.enabled` is off inside this container (see Section 2); remove if testing shows it is not required.
- **Drop**: `registry.npmjs.org`, the entire GitHub IP-range-fetching block (`curl https://api.github.com/meta` and everything that consumes it), `sentry.io`, `statsig.anthropic.com`, `statsig.com`, `marketplace.visualstudio.com`, `vscode.blob.core.windows.net`, `update.code.visualstudio.com`.
  None of these are needed by this project's away-mode profile; add any of them back only if a specific, tested need surfaces, not speculatively.
- The script's self-verification block is kept, with its second check retargeted from `api.github.com/zen` (no longer allowlisted) to `api.anthropic.com`, so the script still proves both the deny and the allow paths actually work before Claude Code ever starts.

### `devcontainer.json`: dropped entirely

Replaced by `docker-sandbox/run.sh`, which does `docker build` and `docker run` directly with the equivalent flags upstream's `devcontainer.json` specified, minus the VS Code `customizations` block:

- `--cap-add=NET_ADMIN --cap-add=NET_RAW`, required for the firewall script's `iptables`/`ipset` calls inside the container.
- Volume mount for the project directory (bound to `/workspace`).
- **Host credential mounts (`~/.claude` and `~/.claude.json`), superseded on 2026-07-02.** The original attempt bind-mounted `~/.claude.json` into the container, first at `/home/node/.claude.json` (wrong: `run.sh` sets `CLAUDE_CONFIG_DIR=/home/node/.claude`, which redirects config lookups there instead, producing `Not logged in · Please run /login`), then at the corrected `/home/node/.claude/.claude.json`. That fix resolved the path mismatch but not the underlying problem: authentication still failed. Investigated via `jq 'keys' ~/.claude.json` (safe: reveals field names only, not values) and found no `accessToken`, `apiKey`, or similarly named field; only an `oauthAccount` key, which almost certainly holds account metadata rather than the bearer token. Conclusion: the real credential lives in macOS Keychain, which has no equivalent inside a Linux container and cannot be brought in by any bind mount, regardless of path. Full investigation in `docker_sandbox_test_findings.md`.
- **Current design, replacing the host-mount approach entirely**: no `~/.claude` or `~/.claude.json` host bind mount at all. Instead, a Docker named volume (`claude-sandbox-config`) mounted at `/home/node/.claude`, giving the container its own independent Claude Code identity, authenticated once via a one-time interactive `claude` session inside the container to complete `/login` (an ordinary "new device" login), persisted in the volume across future runs.
  Chosen over trying to make host-credential sharing work, for two reasons: writing a freshly-generated token back into the host's live `~/.claude.json` (unavoidable with a bind mount, since it shares the same inode) risks mutating the credentials backing the host's actual, currently-active Claude Code sessions, for uncertain benefit given the token likely was not stored there in the first place; and an independent container identity fits this whole exercise's isolation goal better than sharing state would. Tradeoff: the container's Claude Code instance does not share conversation history or auto-memory with host sessions, which is the right tradeoff for an away-from-computer, unattended profile, not a cost.
  Not yet implemented; `run.sh` still reflects the old host-mount approach as of this writing.
- The same environment variables upstream set (`NODE_OPTIONS`, `CLAUDE_CONFIG_DIR`).
- Runs `sudo /usr/local/bin/init-firewall.sh` on container start (the Dockerfile already grants the `node` user passwordless sudo for exactly this script, matching upstream), then execs into `claude --settings /home/node/container-settings.json --permission-mode auto` (see Section 2 for why `--settings` is needed here).

## 2. Design decision: Claude Code's own `sandbox.enabled` stays off inside this container

- This container runs Linux.
  Claude Code's own sandbox uses `bwrap` (bubblewrap) on Linux, a different enforcement mechanism than the macOS Seatbelt path tested and found broken in `sandbox_automode_plan.md`.
  There is no evidence either way on whether bubblewrap's network filtering has the same bug; that finding was specific to the Seatbelt/local-proxy path on macOS and has not been retested here.
- Regardless of that open question, layering it on top would likely be redundant for the filesystem side specifically.
  Docker's own bind mounts already scope what is visible inside the container's filesystem to just the explicit mounts (`/workspace`, `/home/node/.claude`).
  There is no `~/.ssh` or any other host path to expose by accident, since unmounted host paths do not exist inside the container's filesystem namespace at all.
  This is a stronger guarantee than the host-level `denyRead`/`allowRead` approach in `sandbox_automode_plan.md`, which technically exposes the path in the filesystem namespace and relies on a rule to deny it.
- Nested sandboxing (bubblewrap inside a Docker container) can also fail to start depending on what kernel namespace capabilities Docker grants by default, independent of whether it would help if it did start.
- Decision: leave `sandbox.enabled` unset or `false` for sessions run inside this container.
  The container's own `iptables`-based network isolation is the network enforcement layer; Docker's mount scoping is the filesystem enforcement layer.
  Revisit only if a specific gap is found that neither of those two covers.
- **Confirmed necessary, not just theoretical, via live testing on 2026-07-02**: the first end-to-end test run failed to start Claude Code at all, with `Error: sandbox required but unavailable: sandbox is enabled but dependencies are missing: bubblewrap (bwrap) not installed, socat not installed` plus `sandbox.failIfUnavailable is set — refusing to start without a working sandbox`.
  Root cause: `run.sh` bind-mounts the project directory to `/workspace`, so the container also sees this project's `.claude/settings.json`, including the `sandbox.enabled: true` / `failIfUnavailable: true` built for the native macOS setup in `sandbox_automode_plan.md`.
  Fixed by adding `docker-sandbox/container-settings.json` (`{"sandbox": {"enabled": false}}`), baked into the image via `COPY --chown=node:node` in the `Dockerfile`, and passed to the `claude` invocation in `run.sh` via `--settings /home/node/container-settings.json`.
  This overrides just this one key for container sessions without touching the host's project settings, which must keep `sandbox.enabled: true` for native sessions to stay protected.

## 3. Test plan and results

Executed 2026-07-02.
Results recorded inline below rather than kept as a pure forward-looking checklist, since the first run surfaced real, fixed issues (Section 2's nested-sandbox conflict, and the `~/.claude.json` mount noted in Section 1).

1. **Prerequisite check.** Docker Desktop must actually be running, not just installed.
   **Result: passed, with a real gotcha.** The Docker CLI was already installed (v27.4.0), but Docker Desktop would not launch from within any sandboxed Claude Code session in this project, since launching a GUI app requires IPC the sandbox's `denyRead: ["~/"]`/process-access restrictions block. Confirmed this is not Docker-specific: `ps aux` and `open -a Docker` both failed the same way. The user started Docker Desktop manually, outside any Claude Code session, which resolved it.
   A second, related gotcha surfaced immediately after: Docker Desktop on macOS puts its daemon socket at `~/.docker/run/docker.sock`, also outside the sandbox's allowed paths, so even a running daemon was unreachable from a sandboxed session. **This confirms the two sandboxing approaches are not meant to nest**: the Docker-based sandbox must be launched from a plain, unsandboxed terminal, not from inside a Claude Code session bound by this project's native sandbox config. Deliberately not fixed by widening the native sandbox's allowed paths to include `~/.docker`, since Docker socket access is close to root-equivalent and would undermine the sandbox being hardened in `sandbox_automode_plan.md`.
2. **Build.** `docker build -t claude-code-sandbox docker-sandbox/` from a plain terminal.
   **Result: passed**, once run outside the sandbox per step 1. First build took roughly 25 minutes, almost entirely spent pulling the ~250MB `node:20` base image over a slow connection; this is a one-time cost, cached for future builds.
3. **Firewall self-verification.** `init-firewall.sh`'s own built-in check: `https://example.com` should be unreachable, `https://api.anthropic.com` should be reachable.
   **Result: passed.** `api.anthropic.com` and `downloads.claude.ai` resolved and allowlisted; the script's own verification confirmed both the deny and the allow paths.
4. **Positive path.** Run `claude` inside the container and confirm it starts and responds normally, proving `api.anthropic.com` access works end-to-end, not just at the TCP level step 3 confirms.
   **Result: still blocked, after three rounds of fixes.** First attempt hit the nested-sandbox conflict (Section 2, fixed). Second attempt hit the credentials-mount path mismatch (Section 1, fixed). Third attempt, with both fixes in place, still failed with `Not logged in · Please run /login`; diagnosed as the auth token living in macOS Keychain rather than `~/.claude.json`, so no bind mount could bring it in regardless of path (Section 1). Not resolvable by a mount fix; needs the named-volume/independent-login redesign in Section 1 before this step can pass. Full round-by-round detail in `docker_sandbox_test_findings.md`.
5. **Negative path.** From inside the running container, attempt `curl https://example.com` directly, independent of the script's own self-check.
   **Result: passed.** `curl -v` failed with `No route to host` / `Network is unreachable`, confirming the block holds under a fresh, separate attempt, not just within the firewall script's own verification.
6. **Filesystem check.** Confirm host paths outside the explicit mounts are not visible at all from inside the container, not merely access-denied.
   **Result: passed.** `/Users` does not exist inside the container's filesystem (`No such file or directory`); only the mounted `/workspace` and standard Linux system directories are present.
7. **Open question, not yet tested:** does removing `downloads.claude.ai` from the allowlist break anything (Claude Code startup, self-update checks)?
   Test with it present, then test again with it removed, and compare.
8. **Open question, not yet tested:** does removing the Sentry/Statsig telemetry domains cause any startup errors, warnings, or hangs, or does Claude Code degrade gracefully when they are unreachable?
   Test empirically rather than assuming either outcome.
9. **Next step:** implement Section 1's named-volume/independent-login redesign, then retest step 4 (positive path) against a container with its own authenticated identity rather than a host-credential mount.
10. Log the outcome as a dated `CHANGELOG.md` entry, matching this repo's established convention, once steps 3 through 6 all show the expected pass/fail pattern and step 4 passes with the redesigned auth approach.

## 4. Open questions carried into implementation

- Whether `gh`, `git-delta`, `zsh`, and the `powerline10k` theme (general dev-environment niceties, unrelated to security) are worth trimming for a leaner image.
  No security implication either way; purely image size and build time.
  Not addressed by this plan; leave as upstream defaults unless it becomes a real annoyance.
- Whether Claude Code's own `sandbox.enabled` inside this container (Section 2's open question about bubblewrap) is ever worth testing directly, out of curiosity or as an additional layer, once the primary container-level network isolation is confirmed working.

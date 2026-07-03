# Sandbox + Auto Mode Implementation Plan

Goal: run Claude Code autonomously in this project using permission mode `auto`, with Claude Code's built-in OS-level `sandbox` as a hard backstop, per the decision already recorded in `TODO.md` dated 2026-07-02.

This plan does not revisit whether to use both.
It only covers how.

Scoped 2026-07-02 to the away-from-computer/unattended use case specifically: this sandbox profile is for sessions run while the user is away, with nobody available to review a `lavish-axi` browser session.
`lavish-axi` and its local review-server dependencies are therefore deliberately excluded from this config.
Interactive sessions where `lavish-axi` is used happen outside this sandboxed profile.

Note on terminology: "auto mode" (`--permission-mode auto`) and `--dangerously-skip-permissions` (`bypassPermissions`) are two distinct, non-overlapping permission modes in current Claude Code, not the same thing described two ways.
Auto mode is the classifier-reviewed mode, which is what pairs with the sandbox for defense-in-depth.
`bypassPermissions` disables safety checks entirely, and Anthropic's own docs say to use auto mode instead for exactly this reasoning.
This plan is built around `--permission-mode auto`, not the bypass flag.

## 1. The concrete `sandbox` block for this project

Add a `sandbox` key as a sibling of the existing `env` key in `.claude/settings.json`.
There is no key collision, and no behavior change to the existing `env.LAVISH_AXI_TELEMETRY` setting.
Sandboxed Bash subprocesses inherit the parent process environment by default, including anything set via the `env` block, and `LAVISH_AXI_TELEMETRY` is not on any credentials deny list, so it keeps working unchanged.

```json
{
  "env": {
    "LAVISH_AXI_TELEMETRY": "0"
  },
  "sandbox": {
    "enabled": true,
    "autoAllowBashIfSandboxed": true,
    "allowUnsandboxedCommands": false,
    "failIfUnavailable": true,
    "excludedCommands": [],
    "filesystem": {
      "allowWrite": [],
      "denyRead": ["~/"],
      "allowRead": ["."]
    },
    "network": {
      "allowedDomains": [],
      "deniedDomains": []
    },
    "credentials": {
      "files": [
        { "path": "~/.ssh", "mode": "deny" }
      ],
      "envVars": []
    }
  }
}
```

Updated 2026-07-02: this block originally invoked `lavish-axi` through `npx -y lavish-axi <file>`, which needed `registry.npmjs.org` and `~/.npm`.
That was revised after confirming `lavish-axi` is already installed globally on this machine (`which lavish-axi` resolves to `/usr/local/bin/lavish-axi`, a symlink into `/usr/local/lib/node_modules/lavish-axi`, and `npm list -g lavish-axi` confirms version `0.1.35` installed globally).
Invoking the binary directly as `lavish-axi <file>` instead of through `npx` removes the npm-registry network dependency and the `~/.npm` filesystem dependency entirely, both of which existed only to support `npx`'s package resolution and caching, not anything `lavish-axi` itself needs.

Rationale for each non-obvious choice, grounded in this specific repo:

- `allowWrite: []`. This sandbox profile is scoped to away-from-computer/unattended sessions (see the note at the top of this document), where `lavish-axi` is not used, so `~/.lavish-axi` is deliberately not granted here even though it was confirmed as the one path `lavish-axi` itself touches (via `LAVISH_AXI_STATE_DIR || path.join(os.homedir(), ".lavish-axi")` in `/usr/local/lib/node_modules/lavish-axi/dist/cli.mjs`). The sandbox's default write scope (cwd plus `$TMPDIR`) already covers everything else this repo does (`scaffold_skill.sh` only writes inside `.agents/skills/` and `.claude/skills/`). If `lavish-axi` is later needed inside this sandboxed profile, re-add `~/.lavish-axi` to both `allowWrite` and `allowRead`, and re-add `network.allowLocalBinding: true` (removed below for the same reason).
- `denyRead: ["~/"]` paired with `allowRead: ["."]`. This is the broad-deny-plus-targeted-allow pattern from the docs. The default read policy is the whole computer except denied paths, which would otherwise leave `~/.ssh` and anything else in the home directory readable. `allowRead` re-opens only the project directory itself, since nothing else outside cwd needs to be read in this scoped-down, lavish-free profile.
- This block must live in `.claude/settings.json` specifically, not `~/.claude/settings.json`. The `.` prefix in `allowRead` only resolves to the project root when the config lives in project settings; in user settings it would resolve to `~/.claude` instead and silently fail to cover this project.
- `network.allowedDomains: []`. This workflow makes zero outbound network calls once `lavish-axi` is out of scope, so the allowlist is intentionally left empty rather than omitting the `network` key, to make the "this project needs no external network access" property visible directly in the settings file. **Caveat, confirmed 2026-07-02 and not yet resolved**: live testing showed this restriction is not actually enforced by the local sandbox proxy in Claude Code v2.1.198 on macOS; see the dedicated note below. Do not treat an empty `allowedDomains` as a genuine network backstop until that is fixed or better understood.
- One narrow exception not covered by this default-deny posture: `lavish-axi`'s optional `share` subcommand publishes an artifact to a third-party host (`ht-ml.app`), and `export` can leave remote CDN/font references unresolved without network. Neither is relevant to this sandboxed profile, since `lavish-axi` is out of scope here entirely.
- `credentials.files: [{"path": "~/.ssh", "mode": "deny"}]`. Redundant with the broad `denyRead: ["~/"]` above, but added explicitly because `~/.ssh` holds a real, valuable secret on this machine (the `iphone_webssh` keypair from the CHANGELOG's remote-access setup), and the dedicated `credentials` block is meant to keep that intent self-documenting and independent of the general filesystem rule.
- `credentials.envVars: []`. Left empty rather than filled with guessed names. No sensitive-looking environment variable is currently set in this shell, and no `.env` file exists in the repo. Revisit this only when a real credential-bearing env var is actually introduced.
- `allowUnsandboxedCommands: false`. This disables the `dangerouslyDisableSandbox` retry escape hatch. Given the whole point of this setup is a hard backstop for autonomous runs, a silent unsandboxed fallback would defeat it. A blocked command should fail visibly so the allowlist gets fixed, not silently bypass the sandbox.
- `failIfUnavailable: true`. If Seatbelt (macOS) can't start for any reason, Claude Code should refuse to run in auto mode rather than silently falling back to fully unsandboxed execution during an unattended session with nobody watching for a warning banner.
- `autoAllowBashIfSandboxed: true`. This is the sandbox's own "auto-allow" toggle: sandboxed Bash commands run without an additional manual permission prompt, because the OS boundary is what's containing them. This is a different mechanism from the `auto` permission mode (Section 2) and the docs confirm the two work independently and are meant to be combined.

## 2. Enabling auto mode

Auto mode is a permission mode value, not something that is automatic once the sandbox exists. It is set with the `--permission-mode auto` CLI flag (or `defaultMode: "auto"` in settings, with a caveat below), and it is a different mechanism from `--dangerously-skip-permissions` / `bypassPermissions`, which disables checks entirely rather than routing actions through a classifier.

Prerequisites, worth confirming once before relying on this:

- Claude Code v2.1.83 or later.
- A model that supports auto mode (Opus 4.6+/Sonnet 4.6+ on the Anthropic API, which this account is presumably on).
- No organization-level lock via `permissions.disableAutoMode` (not applicable on an individual/solo-dev account).

Critical constraint that changes the implementation: Claude Code v2.1.142 and later ignore `defaultMode: "auto"` set in project-scoped settings (`.claude/settings.json` or `.claude/settings.local.json`), specifically so a repository cannot grant itself auto mode. It only honors `defaultMode: "auto"` from `~/.claude/settings.json` (user settings) or managed settings.

Given this is a solo dev with (presumably) more than one project on the machine, do not set `defaultMode: "auto"` globally in `~/.claude/settings.json`. That would make every project on this machine start in auto mode by default, which is broader than what was asked for here. Instead:

- For interactive sessions in this project: launch with `claude --permission-mode auto` from the project root.
- For unattended/headless runs (the actual "run autonomously" use case): `claude -p "<task>" --permission-mode auto`, which the docs confirm works the same way with the `-p` flag.
- Optional convenience, not required for this plan's core deliverable: add a tiny project-local wrapper script (for example `./run-auto.sh` invoking `claude --permission-mode auto "$@"`) so the flag doesn't need to be retyped. Leave this for a follow-up if wanted; it's a nice-to-have, not a dependency of Section 1.

## 3. Domain and filesystem allow-lists, grounded in what this repo actually does

Investigated directly rather than assumed:

- No `package.json`, `requirements.txt`, or lockfile anywhere in the repo. This project does not install its own dependencies.
- No `.env` file, no code that calls external APIs.
- `skill-creator`'s `scaffold_skill.sh` stays entirely inside the project directory (default sandbox write scope already covers it), needs nothing extra.
- The two still-empty skill stubs, `session-start` and `session-wrapup` (tracked in the other `TODO.md` item), currently do nothing and need no sandbox allowances. If they're later filled in and start running `git` commands against a remote (for example `git push` once this repo gets a git remote), that would need a network domain such as `github.com` added at that point. Do not pre-add it now without evidence; a local-only `git init`/`git commit` needs no network allowance at all.

### `lavish-axi` findings, retained for context, not active in this profile

This sandbox profile is scoped to away-from-computer/unattended sessions, where `lavish-axi` is not used (see the note at the top of this document), so none of the following drove a Section 1 allowance in the current config.
They are kept here in case `lavish-axi` is ever added back into a sandboxed profile.

- Confirmed by reading the installed package's source directly (`/usr/local/lib/node_modules/lavish-axi/dist/cli.mjs`) that `lavish-axi <file>`, invoked directly rather than through `npx`, needs only `~/.lavish-axi` (filesystem) and no outbound network access for its own state and local server.
- The project's `.agents/skills/lavish/SKILL.md` used to hardcode `npx -y lavish-axi ...` in every documented command. Resolved on 2026-07-02 by editing `SKILL.md` to invoke `lavish-axi` directly everywhere instead, logged in `skills-lock.json`'s new `localModifications` field, and recorded in `CHANGELOG.md`. This is independent of whether `lavish-axi` is ever included in a sandboxed profile.
- `lavish-axi`'s local review server, spawned as a child of a sandboxed Bash command, failed to bind with `listen EPERM: operation not permitted 127.0.0.1:4387` under the sandbox's default network policy, which blocks local port binding even for loopback-only addresses. `network.allowLocalBinding: true` fixed it; would need to be re-added if `lavish-axi` returns to this profile.
- Even with the server reachable, the browser did not auto-open. Traced to `lavish-axi`'s use of the npm `open` package (`cli.mjs`: `const open = (await import("open")).default; await open(response.url);`), which on macOS shells out to `/usr/bin/open` and requires Apple Events access. The relevant sandbox setting, `sandbox.allowAppleEvents`, is documented as removing code-execution isolation and is only honored from user-level settings, never project-scoped `.claude/settings.json`. Decided not to enable it machine-wide for a convenience feature; the review server still starts and prints a session URL to open manually.

### Confirmed, unresolved limitation: `network.allowedDomains`/`deniedDomains` are not enforced

Tested live on 2026-07-02 against Claude Code v2.1.198 on macOS, independent of the `lavish-axi` scoping decision above, since this affects the sandbox's core network backstop property.

- Confirmed via `env` inside a sandboxed Bash session that `HTTP_PROXY`/`HTTPS_PROXY`/`ALL_PROXY` point to a local authenticating proxy (`http://srt:<password>@localhost:<port>`), which sandboxed commands are expected to route through for network egress, matching the `network.httpProxyPort`/`socksProxyPort` fields documented in the settings schema.
- `curl https://example.com` and `curl http://example.com` both succeeded with `allowedDomains: []` (nothing allowed), returning full page content instead of being denied.
- Ruled out an "empty array means no filter" theory specifically: retested with `allowedDomains: ["registry.npmjs.org"]` (a populated allowlist that deliberately excludes `example.com`). `example.com` still succeeded. The domain allowlist does not appear to be enforced by the local proxy at all right now, for either HTTP or HTTPS, regardless of whether it is empty or populated.
- Verbose `curl -v` output confirmed the proxy actively participates and responds `HTTP/1.1 200 Connection Established` (HTTPS `CONNECT`) or `200 OK` (plain HTTP `GET`) for a domain that should have been denied, rather than the request bypassing the proxy some other way.
- Every other sandbox layer tested in the same live session worked correctly: filesystem `allowWrite`/`denyRead`/`allowRead` restrictions, `network.allowLocalBinding`, `autoAllowBashIfSandboxed`, and `allowUnsandboxedCommands: false` / strict sandbox mode (confirmed via `/sandbox`'s Config/Mode/Overrides tabs and an actual denied filesystem write producing a `sandbox-exec`-style "operation not permitted" error). Only network domain filtering is affected.
- **Not investigated further**: whether this is a known/documented Claude Code limitation, whether `network.tlsTerminate` (marked `[EXPERIMENTAL]` in the settings schema, described as needed for HTTPS request-body inspection) is a missing prerequisite, or whether this is a genuine bug. Decided 2026-07-02 to stop at documenting the finding rather than continue investigating, since this sandbox profile's actual network need is zero domains either way (see the `allowedDomains: []` rationale above) — the practical exposure from this gap is that a compromised/injected action could still reach the network despite the config appearing to deny it, not that legitimate work is blocked.
- **Do not treat `sandbox.network.allowedDomains`/`deniedDomains` as a trustworthy hard backstop until this is understood or fixed.** The filesystem and local-bind restrictions remain trustworthy based on live testing; the network domain layer specifically does not.
- **Retested 2026-07-03 against Claude Code v2.1.200** (two patch versions past the original v2.1.198 finding, sandbox re-enabled via `/sandbox` for this session specifically to make the retest meaningful).
  Same result: `curl https://example.com` with `allowedDomains: []` returned HTTP 200, and `curl -v` confirmed the proxy actively issued `HTTP/1.1 200 Connection Established` for the CONNECT tunnel rather than denying it.
  The bug is not fixed as of v2.1.200.
  Not re-tested this round: the populated-allowlist variant (`allowedDomains: ["registry.npmjs.org"]`), since the empty-list case alone already reproduces the same unresolved behavior as the original finding.

## 4. Test plan and results

Run inside the sandbox-and-auto-mode session itself, so it validates the real combined setup rather than a mocked one.
Executed 2026-07-02 against Claude Code v2.1.198 on macOS; results recorded inline below rather than kept as a speculative checklist, since the profile changed mid-testing (lavish-axi scoped out; local-bind and network findings surfaced and were acted on, per Section 3).

1. **Confirm config loaded.** Run `/sandbox` inside a Claude Code session. As of v2.1.198, the menu tabs are `Sandbox`, `Mode`, `Overrides`, `Config`, not `Dependencies`/`Config` as originally assumed; Seatbelt availability is confirmed implicitly, since `failIfUnavailable: true` means the session would have refused to start at all if Seatbelt were unavailable. **Result: passed.** `Config` tab's resolved filesystem read/write restrictions matched what was on disk, `Mode` tab showed "Sandbox BashTool, with auto-allow" selected (`autoAllowBashIfSandboxed: true`), `Overrides` tab showed "Strict sandbox mode" as current (`allowUnsandboxedCommands: false`).
2. **Launch in auto mode.** `claude --permission-mode auto` from the project root. A session started with plain `claude` (no flag) is not in auto permission mode even with the sandbox config correctly loaded; this was caught mid-test (an earlier attempt used plain `claude`) and corrected by restarting with the flag.
3. **Positive path.** Originally exercised via the `lavish` skill (create a throwaway file, open it with `lavish-axi`); superseded once the profile was scoped to exclude `lavish-axi` entirely (see the note at the top of this document). **Result: passed** while `lavish-axi` was still in scope, including surfacing the `network.allowLocalBinding` gap (Section 3) and the Apple Events browser-auto-open limitation (Section 3). Not re-run after descoping `lavish-axi`, since the remaining positive-path surface (in-project file writes, sandboxed Bash) is already covered by step 1's config checks.
4. **Negative path.** Attempted two out-of-scope actions and observed the result: write to `~/Desktop/sandbox-test-should-fail.txt` (outside `allowWrite`), and fetch `https://example.com` (not on `allowedDomains`). **Filesystem write: passed.** Denied with a `sandbox-exec`-style `(eval):1: operation not permitted` error, exit code 1, no silent unsandboxed retry. **Network fetch: failed.** Succeeded and returned full page content, both with `allowedDomains: []` and with `allowedDomains: ["registry.npmjs.org"]` (a populated allowlist that still excludes `example.com`). Root-caused to the local proxy not enforcing domain filtering at all, for either HTTP or HTTPS; documented as an unresolved, confirmed limitation in Section 3. Decided 2026-07-02 not to investigate further, since this profile needs zero network access either way.
5. **Read-side negative test.** Asked to list or read `~/.ssh`. **Result: passed**, denied, confirming both `denyRead: ["~/"]` and the explicit `credentials.files` entry work.
6. **Clean up.** Deleted `.scratch/sandbox-test.*` and closed the `lavish-axi` session opened during step 3, from before the profile was scoped down.
7. **Trust verdict, revised from the original all-or-nothing gate**: the filesystem and Bash-sandboxing layers (steps 1, 4's filesystem half, 5) are confirmed trustworthy as a hard backstop. The network domain-filtering layer (step 4's network half) is confirmed **not** trustworthy and must not be relied on, though this profile's actual network need is already zero regardless. Given that, this setup is usable for the away-from-computer scope it's now built for, with the explicit caveat that a compromised or injected action could still reach the network despite the config appearing to deny it. Logged in `CHANGELOG.md`.

## 5. AGENTS.md conventions applied to this plan and its execution

- No em dash used anywhere in this document.
- Long-form prose sections use one full sentence per line, per the markdown convention.
- If this plan is later committed, the commit message must not add an agent name as co-author.
- Every concrete choice above (narrow enumerated allowlists instead of broad convenient ones, `failIfUnavailable: true`, `allowUnsandboxedCommands: false`) picks robustness and simplicity over developer convenience, per the stated priority order.
- Section 4's requirement to validate end-to-end, including a deliberate negative/failure case, before trusting the setup mirrors AGENTS.md's bug-fix discipline of reproducing E2E before declaring something fixed, applied here to a safety config instead of a bug.
- If whoever implements this notices any unrelated issue along the way (malformed JSON, a stray skill stub, etc.), fix it inline rather than leaving it, per AGENTS.md's "fix issues you notice" rule.

# Research: Adversarial Review of `sandbox_automode_plan.md`

Date: 2026-07-02

Scope: the one item checked off in `TODO.md` under "Set up a sandbox to run Claude Code with `--dangerously-skip-permissions`", specifically "Draft an implementation plan for enabling both auto mode and the sandbox config together."
Every factual claim below was checked against the live Claude Code docs (`/en/permissions`, `/en/permission-modes`, `/en/sandboxing`) and this repo's own files, not taken from the plan at face value.

## Finding 1: auto mode's own safety disclaimer is missing from the plan

The official docs state, in `/en/permission-modes`:

> Auto mode is a research preview. It reduces permission prompts but does not guarantee safety. Use it for tasks where you trust the general direction, not as a replacement for review on sensitive operations.

Neither `TODO.md` nor `sandbox_automode_plan.md` mentions this.
The plan's stated purpose is to justify trusting auto mode for unattended "real work" (`sandbox_automode_plan.md` Section 4, step 7: "Only trust the combined setup for real unattended work once steps 3 through 5 all show the expected pass/fail pattern").
The single most relevant caveat to that goal, a direct vendor warning that the mechanism does not guarantee safety, is never surfaced or weighed against the plan's conclusion.

Recommendation: add this caveat to Section 2 of `sandbox_automode_plan.md` before treating a passing test run as license to trust the setup unsupervised.

## Finding 2: the network allowlist audit missed a real domain documented by the cited source

`sandbox_automode_plan.md` Section 3 claims:

> Investigated directly rather than assumed... the only outside-cwd, outside-default-scope behavior comes from the lavish skill's `npx -y lavish-axi <file>` invocation, which needs `registry.npmjs.org`... No other repo code makes outbound network calls.

`.agents/skills/lavish/SKILL.md` line 73, the very skill this claim cites, documents a second command:

> Run `npx -y lavish-axi share <html-file> [--password <pw>] [--token <t>]` to publish the artifact on ht-ml.app (https://ht-ml.app), a third-party hosting service not part of Lavish, and get back a visitable URL.

This is a Bash-sandboxed `npx` call, the same code path already audited, reaching a domain (`ht-ml.app`) not on the plan's `allowedDomains` list.
Combined with the plan's own `allowUnsandboxedCommands: false`, the first time anyone asks to share an artifact after this config lands, the `share` command fails hard with no retry path.
This directly contradicts the "investigated directly" claim in Section 3.

Recommendation: add `ht-ml.app` to `network.allowedDomains` in Section 1's JSON block, or explicitly document it as a known, accepted gap if artifact sharing is out of scope for this project.

## Finding 3: the model-support prerequisite is flagged but never verified

`sandbox_automode_plan.md` Section 2 states the auto mode model gate as "Opus 4.6+/Sonnet 4.6+ on the Anthropic API, which this account is presumably on."
The word "presumably" is the plan's own admission that this was never checked.
It is a load-bearing prerequisite for the CLI invocations the rest of Section 2 is built around.

Recommendation: confirm the active model and provider (`/model`, account plan) before relying on Section 2's invocation instructions.

## What held up under verification

Every specific, checkable claim in the plan that was cross-referenced against the live docs turned out accurate:

- Auto mode requires Claude Code v2.1.83 or later, confirmed verbatim in `/en/permission-modes`.
- Claude Code v2.1.142 and later ignore `defaultMode: "auto"` in project-scoped settings, confirmed verbatim.
- Domain approvals persisting for the current session as of v2.1.191, confirmed verbatim.
- The Opus 4.6+/Sonnet 4.6+ model gate on the Anthropic API, confirmed verbatim (see Finding 3 for why this needs re-checking against this specific account regardless).
- The "use both for defense-in-depth" recommendation and the filesystem/network restriction-merging behavior, confirmed near-verbatim in `/en/permissions`.
- `network.allowLocalBinding`, flagged in Section 3 as an "open uncertainty" rather than asserted as fact, is a real, valid sandbox setting, confirmed against the `anthropics/claude-code` example configs on GitHub.
- The filesystem paths (`~/.lavish-axi`, `~/.npm`) and their claimed contents, confirmed by direct inspection of this machine.
- The `iphone_webssh` keypair claim in Section 1's rationale, confirmed against `CHANGELOG.md` and `~/.ssh` contents.
- No `package.json`, `requirements.txt`, or lockfile in this repo, confirmed by direct search.

## Overall assessment

The checkbox is fairly earned for "draft a plan": the deliverable is real, detailed, and mostly well-sourced against current docs, not fabricated.
It is not yet safe to execute the remaining unchecked `TODO.md` steps (apply the sandbox block, run the test plan) without first addressing Finding 1 and Finding 2.
Finding 3 should be a quick confirmation, not a blocker.

---
name: autonomous-queue-instructions
description: Use when the user wants to check whether they're ready to run the autonomous-queue skill, or asks how to start an unattended queue run - checks whether the current session is inside the project's Docker sandbox and, if not, explains how to start one.
---

# autonomous-queue-instructions Skill Instructions

Preflight check before `/autonomous-queue`. Never processes tasks itself.

## Steps

1. Run `echo "$DEVCONTAINER"`. The container's Dockerfile sets this to `true`; a bare host session leaves it unset.
2. If it prints `true`: report the environment is ready, tell the user they can run `/autonomous-queue` directly in this session.
3. If not: tell the user to open a plain, unsandboxed terminal (not a sandboxed Claude Code session - Docker's socket falls outside this project's native sandbox allowlist) and run `./docker-sandbox/run.sh` from the project root. This builds the image if needed and drops them into an interactive session inside the container, where they can pick whichever model/CLI they want and run `/autonomous-queue`.
4. Also confirm `queue/*.md` has at least one pending task, and that `command -v gnhf` succeeds.

#!/bin/bash
set -euo pipefail

# Builds and runs the network-isolated Claude Code sandbox.
# Replaces Anthropic's devcontainer.json (VS Code Dev Containers abstraction, unused here)
# with a plain docker build/run, per docker_sandbox_plan.md Section 1.
#
# Usage:
#   ./run.sh                          interactive session, --permission-mode auto
#   ./run.sh -p "some task"           headless one-shot run, forwarded to `claude`

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
IMAGE_NAME="claude-code-sandbox"

echo "Building $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" "$SCRIPT_DIR"

echo "Starting sandboxed Claude Code session..."
docker run --rm -it \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$PROJECT_ROOT:/workspace" \
  -v claude-sandbox-config:/home/node/.claude \
  -e NODE_OPTIONS="--max-old-space-size=4096" \
  -e CLAUDE_CONFIG_DIR="/home/node/.claude" \
  "$IMAGE_NAME" \
  bash -c 'sudo /usr/local/bin/init-firewall.sh && exec claude --settings /home/node/container-settings.json --permission-mode auto "$@"' bash "$@"

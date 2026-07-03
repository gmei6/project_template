#!/bin/bash
set -euo pipefail

# Host-side entry point for the overnight-queue skill. Builds and runs the
# same docker-sandbox image as docker-sandbox/run.sh, but execs
# queue-runner.sh inside the container instead of an interactive claude
# shell. docker-sandbox/run.sh itself is untouched; this is a sibling, not
# a replacement.
#
# Usage:
#   ./run-queue.sh --until "07:00" [--max-retries 3]
#
# Prerequisites (not set up by this script): docker-sandbox/ must exist in
# the target project (see docker_sandbox_plan.md), Docker must be running,
# and the project must already be a git repository.

UNTIL=""
MAX_RETRIES=3

while [ "$#" -gt 0 ]; do
  case "$1" in
    --until)
      UNTIL="$2"; shift 2 ;;
    --max-retries)
      MAX_RETRIES="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 --until \"<time>\" [--max-retries N]" >&2
      exit 1 ;;
  esac
done

if [ -z "$UNTIL" ]; then
  echo "Usage: $0 --until \"<time>\" [--max-retries N]" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
DOCKER_SANDBOX_DIR="$PROJECT_ROOT/docker-sandbox"
IMAGE_NAME="claude-code-sandbox"

if [ ! -d "$DOCKER_SANDBOX_DIR" ]; then
  echo "Error: $DOCKER_SANDBOX_DIR not found. This skill depends on the project's" >&2
  echo "existing Docker sandbox (see docker_sandbox_plan.md)." >&2
  exit 1
fi

if ! git -C "$PROJECT_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Error: $PROJECT_ROOT is not a git repository. git init it first." >&2
  exit 1
fi

echo "Building $IMAGE_NAME..."
docker build -t "$IMAGE_NAME" "$DOCKER_SANDBOX_DIR"

echo "Starting overnight-queue run (until: $UNTIL, max-retries: $MAX_RETRIES)..."
docker run --rm \
  --cap-add=NET_ADMIN \
  --cap-add=NET_RAW \
  -v "$PROJECT_ROOT:/workspace" \
  -v claude-sandbox-config:/home/node/.claude \
  -e NODE_OPTIONS="--max-old-space-size=4096" \
  -e CLAUDE_CONFIG_DIR="/home/node/.claude" \
  "$IMAGE_NAME" \
  bash -c 'sudo /usr/local/bin/init-firewall.sh && exec /workspace/.agents/skills/overnight-queue/scripts/queue-runner.sh --until "$1" --max-retries "$2"' \
  bash "$UNTIL" "$MAX_RETRIES"

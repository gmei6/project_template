#!/bin/bash
set -uo pipefail
# Runs inside docker-sandbox. Processes queue/*.md sequentially, one gnhf
# run per task, until the queue is empty or --until is reached (or forever
# if --until is "indefinite"/omitted). Full rationale: ../references/design.md.
#
# Usage (inside the container):
#   queue-runner.sh [--until "<date -d compatible string>" | "indefinite"]

PROJECT_ROOT="/workspace"
QUEUE_DIR="$PROJECT_ROOT/queue"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
LOG="$QUEUE_DIR/run.log"

UNTIL="indefinite"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --until) UNTIL="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

DEADLINE=""
if [ "$UNTIL" != "indefinite" ]; then
  DEADLINE="$(date -d "$UNTIL" +%s)"
  if [ -z "$DEADLINE" ]; then
    echo "Error: could not parse --until value '$UNTIL'" >&2
    exit 1
  fi
fi

mkdir -p "$DONE_DIR" "$FAILED_DIR"

log() { echo "[$(date -Iseconds)] $*" | tee -a "$LOG"; }
now_epoch() { date +%s; }
looks_rate_limited() { printf '%s' "$1" | grep -iqE 'rate.?limit|usage limit|quota|try again|429'; }

BACKOFF_SECONDS=900
backoff() {
  local wait=$BACKOFF_SECONDS
  if [ -n "$DEADLINE" ]; then
    local remaining=$(( DEADLINE - $(now_epoch) ))
    if [ "$remaining" -le 0 ]; then
      log "backoff: stop time already reached, not waiting further"
      return 1
    fi
    [ "$wait" -gt "$remaining" ] && wait=$remaining
  fi
  log "backoff: sleeping ${wait}s"
  sleep "$wait"
  BACKOFF_SECONDS=$(( BACKOFF_SECONDS * 2 ))
  [ "$BACKOFF_SECONDS" -gt 7200 ] && BACKOFF_SECONDS=7200
  return 0
}

# Returns: 0 = task resolved (done, failed, or rate-limited-and-backed-off --
# caller should loop and re-scan queue/), 1 = deadline passed mid-backoff
# (caller should stop).
run_task() {
  local task="$1" task_name out prompt
  task_name=$(basename "$task")
  # Scope the agent to just this task. Without this, the spawned agent can
  # notice other repo-visible skills (e.g. no-mistakes) and try to run them
  # as an unrequested "wrap up" step, which fails in this sandbox for
  # environment reasons unrelated to the task itself. See references/design.md.
  prompt="Complete only the following task. Do not invoke any other skill,
validation pipeline, or push/PR workflow (including no-mistakes) as part of
finishing it - just do the described work and stop once it's done.

$(cat "$task")"
  # Without --stop-when, gnhf's schema has no should_fully_stop field, so a
  # finished task has no clean way to end the loop -- it either iterates
  # forever re-verifying itself or, observed live, starts reporting
  # success=false just to trigger gnhf's 3-consecutive-failures abort, which
  # prints "gnhf stopped" and gets this script's run_task treated as a real
  # failure even though the actual work already succeeded. See references/design.md.
  out="$(cd "$PROJECT_ROOT" && gnhf --agent claude --worktree --stop-when "the task described in the prompt is fully complete and no further changes are needed" "$prompt" 2>&1)"

  # gnhf's exit code is not reliable -- it exits 0 even on an aborted run.
  # Outcome comes from its printed exit-summary title instead. With
  # --stop-when set, every headless run prints "gnhf stopped" (never "gnhf
  # wrapped" -- that title is reserved for an interactive Ctrl+C), including
  # ones that finished cleanly, so success is "stop condition met" in the
  # subtitle, not the title. See references/design.md.
  if printf '%s' "$out" | grep -qE "gnhf wrapped|before: stop condition met"; then
    mv "$task" "$DONE_DIR/"
    log "done: $task_name"
    BACKOFF_SECONDS=900
    return 0
  fi

  if looks_rate_limited "$out"; then
    log "rate-limited: $task_name, backing off"
    backoff || return 1
    return 0   # loop re-scans queue/, picks up the same file again
  fi

  mv "$task" "$FAILED_DIR/"
  log "failed: $task_name: $(printf '%s' "$out" | tail -n5 | tr '\n' ' ')"
  BACKOFF_SECONDS=900
  return 0
}

main() {
  log "run start: until=$UNTIL"
  while :; do
    local pending count
    pending=$(find "$QUEUE_DIR" -maxdepth 1 -name '*.md' -type f | sort)
    count=$(printf '%s\n' "$pending" | grep -c . || true)

    if [ "$count" -eq 0 ]; then
      log "queue empty"
      break
    fi

    if [ -n "$DEADLINE" ] && [ "$(now_epoch)" -ge "$DEADLINE" ]; then
      log "stop time reached, $count task(s) remain"
      break
    fi

    run_task "$(printf '%s\n' "$pending" | head -n1)" || break
  done

  local done_n failed_n
  done_n=$(find "$DONE_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  failed_n=$(find "$FAILED_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  log "summary: done=$done_n failed=$failed_n"
  log "run end"
}

main

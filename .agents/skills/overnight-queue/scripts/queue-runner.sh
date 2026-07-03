#!/bin/bash
set -uo pipefail
# Runs inside the docker-sandbox container. Processes queue/*.md sequentially,
# one Haiku attempt per task, paced across the time budget until --until.
# If the primary queue empties early, retries queue/failed/ with any spare
# time. Full design rationale: ../references/design.md.
#
# Usage (inside the container):
#   queue-runner.sh --until "<date -d compatible string>" [--max-retries N]

PROJECT_ROOT="/workspace"
QUEUE_DIR="$PROJECT_ROOT/queue"
DONE_DIR="$QUEUE_DIR/done"
FAILED_DIR="$QUEUE_DIR/failed"
EXHAUSTED_DIR="$QUEUE_DIR/failed-exhausted"
LOG="$QUEUE_DIR/run.log"
WORKTREE_DIR="$PROJECT_ROOT/.worktrees/overnight-queue"
ATTEMPTS_DIR="$QUEUE_DIR/.attempts"
RUN_TS="$(date +%Y%m%d-%H%M%S)"
BRANCH="overnight-queue/$RUN_TS"

UNTIL=""
MAX_RETRIES=3

while [ "$#" -gt 0 ]; do
  case "$1" in
    --until)
      UNTIL="$2"; shift 2 ;;
    --max-retries)
      MAX_RETRIES="$2"; shift 2 ;;
    *)
      echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$UNTIL" ]; then
  echo "Error: --until is required, e.g. --until \"07:00\"" >&2
  exit 1
fi

DEADLINE="$(date -d "$UNTIL" +%s)"
if [ -z "$DEADLINE" ]; then
  echo "Error: could not parse --until value '$UNTIL'" >&2
  exit 1
fi

mkdir -p "$DONE_DIR" "$FAILED_DIR" "$EXHAUSTED_DIR" "$ATTEMPTS_DIR"

log() {
  echo "[$(date -Iseconds)] $*" | tee -a "$LOG"
}

# --- one-time setup: worktree + branch, reused sequentially for the whole run ---
setup_worktree() {
  # git worktree add -b needs a real commit to branch from. Some git versions
  # (e.g. 2.39, this container's) do not infer --orphan on an unborn HEAD the
  # way newer git does, and fail outright instead. Bootstrap with an empty
  # commit rather than requiring every fresh repo to have committed first.
  if ! git -C "$PROJECT_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$PROJECT_ROOT" commit --allow-empty -m "overnight-queue: bootstrap initial commit" >>"$LOG" 2>&1
  fi
  if [ ! -d "$WORKTREE_DIR" ]; then
    git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" -b "$BRANCH" >>"$LOG" 2>&1
  fi
  if ! grep -qxF ".worktrees/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees/" >> "$PROJECT_ROOT/.gitignore"
  fi
}

# --- attempt-count bookkeeping (attempt count lives in $ATTEMPTS_DIR/<basename>) ---
attempt_count() {
  local f="$ATTEMPTS_DIR/$(basename "$1")"
  [ -f "$f" ] && cat "$f" || echo 0
}

bump_attempt_count() {
  local f="$ATTEMPTS_DIR/$(basename "$1")"
  local n
  n=$(attempt_count "$1")
  echo $((n + 1)) > "$f"
}

# --- looks-like-a-rate-limit check on captured output ---
looks_rate_limited() {
  printf '%s' "$1" | grep -iqE 'rate.?limit|usage limit|quota|try again|429'
}

# --- run one task attempt inside the worktree, given the full prompt text ---
# Sets ATTEMPT_OK=1/0 and ATTEMPT_OUTPUT as globals.
run_attempt() {
  local prompt="$1"
  local pre_sha
  pre_sha="$(git -C "$WORKTREE_DIR" rev-parse HEAD)"

  local out
  out="$(cd "$WORKTREE_DIR" && claude -p "$prompt" --model haiku --permission-mode auto --output-format json 2>&1)"
  local exit_code=$?

  ATTEMPT_OUTPUT="$out"

  if [ "$exit_code" -eq 0 ]; then
    ATTEMPT_OK=1
  else
    ATTEMPT_OK=0
    git -C "$WORKTREE_DIR" reset --hard "$pre_sha" >>"$LOG" 2>&1
  fi
}

commit_task() {
  local task_name="$1"
  git -C "$WORKTREE_DIR" add -A
  if ! git -C "$WORKTREE_DIR" diff --cached --quiet; then
    git -C "$WORKTREE_DIR" commit -q -m "$task_name: completed by overnight-queue"
  fi
}

extract_usage_summary() {
  # Defensive: exact JSON field names for cost/usage are unconfirmed. Best effort only.
  printf '%s' "$1" | jq -r '
    if (.total_cost_usd? // .cost_usd?) then
      "cost_usd=" + ((.total_cost_usd // .cost_usd) | tostring)
    else "cost_usd=unknown" end
  ' 2>/dev/null || echo "cost_usd=unknown"
}

now_epoch() { date +%s; }

# --- primary phase: one pass over queue/*.md ---
primary_phase() {
  while :; do
    local pending
    pending=$(find "$QUEUE_DIR" -maxdepth 1 -name '*.md' -type f | sort)
    local count
    count=$(printf '%s\n' "$pending" | grep -c . || true)

    if [ "$count" -eq 0 ]; then
      log "primary phase: queue empty"
      return 0
    fi

    local now=$(now_epoch)
    if [ "$now" -ge "$DEADLINE" ]; then
      log "primary phase: stop time reached, $count task(s) remain"
      return 1
    fi

    local target=$(( (DEADLINE - now) / count ))
    local task
    task=$(printf '%s\n' "$pending" | head -n1)
    local task_name
    task_name=$(basename "$task")

    local start=$(now_epoch)
    run_attempt "$(cat "$task")"
    local elapsed=$(( $(now_epoch) - start ))

    if [ "$ATTEMPT_OK" -eq 1 ]; then
      commit_task "$task_name"
      mv "$task" "$DONE_DIR/"
      log "primary: $task_name done ($(extract_usage_summary "$ATTEMPT_OUTPUT"), ${elapsed}s)"
    elif looks_rate_limited "$ATTEMPT_OUTPUT"; then
      log "primary: $task_name rate-limited, backing off"
      backoff_then_check_deadline || return 1
      continue
    else
      mv "$task" "$FAILED_DIR/"
      bump_attempt_count "$task"
      log "primary: $task_name failed: $(printf '%s' "$ATTEMPT_OUTPUT" | tail -n5 | tr '\n' ' ')"
    fi

    local remaining=$(( target - elapsed ))
    [ "$remaining" -gt 0 ] && sleep "$remaining"
  done
}

BACKOFF_SECONDS=900
backoff_then_check_deadline() {
  local now=$(now_epoch)
  if [ "$now" -ge "$DEADLINE" ]; then
    log "backoff: stop time already reached, not waiting further"
    return 1
  fi
  local wait=$BACKOFF_SECONDS
  local remaining=$(( DEADLINE - now ))
  [ "$wait" -gt "$remaining" ] && wait=$remaining
  log "backoff: sleeping ${wait}s"
  sleep "$wait"
  BACKOFF_SECONDS=$(( BACKOFF_SECONDS * 2 ))
  [ "$BACKOFF_SECONDS" -gt 7200 ] && BACKOFF_SECONDS=7200
  return 0
}

# --- secondary phase: retry queue/failed/ with any spare time ---
secondary_phase() {
  while :; do
    # Pick the retryable task with the fewest attempts so far (ties broken by
    # filename order). Since every queue/failed/ entry starts with the same
    # attempt count after its primary-phase failure, this naturally cycles
    # through all retryable tasks once per "round" before repeating any,
    # rather than hammering the same task until it exhausts its retries.
    local retryable_count=0
    local best="" best_count=999999
    local f
    for f in "$FAILED_DIR"/*.md; do
      [ -e "$f" ] || continue
      local c
      c=$(attempt_count "$f")
      if [ "$c" -lt "$MAX_RETRIES" ]; then
        retryable_count=$((retryable_count + 1))
        if [ "$c" -lt "$best_count" ]; then
          best="$f"
          best_count="$c"
        fi
      fi
    done

    if [ "$retryable_count" -eq 0 ]; then
      log "secondary phase: nothing left retryable"
      return 0
    fi

    local now=$(now_epoch)
    if [ "$now" -ge "$DEADLINE" ]; then
      log "secondary phase: stop time reached, $retryable_count retryable task(s) remain"
      return 1
    fi

    local target=$(( (DEADLINE - now) / retryable_count ))
    local task="$best"
    local task_name
    task_name=$(basename "$task")
    local prior_error
    prior_error=$(grep -A5 "$task_name failed" "$LOG" | tail -n5)

    local prompt
    prompt="$(cat "$task")

Previous attempt failed with the following error, take it into account this time:
$prior_error"

    local start=$(now_epoch)
    run_attempt "$prompt"
    local elapsed=$(( $(now_epoch) - start ))

    if [ "$ATTEMPT_OK" -eq 1 ]; then
      commit_task "$task_name"
      mv "$task" "$DONE_DIR/"
      log "retry: $task_name done ($(extract_usage_summary "$ATTEMPT_OUTPUT"), ${elapsed}s)"
    elif looks_rate_limited "$ATTEMPT_OUTPUT"; then
      log "retry: $task_name rate-limited, backing off"
      backoff_then_check_deadline || return 1
      continue
    else
      bump_attempt_count "$task"
      local n
      n=$(attempt_count "$task")
      log "retry: $task_name failed (attempt $n/$MAX_RETRIES): $(printf '%s' "$ATTEMPT_OUTPUT" | tail -n5 | tr '\n' ' ')"
      if [ "$n" -ge "$MAX_RETRIES" ]; then
        mv "$task" "$EXHAUSTED_DIR/"
        log "retry: $task_name exhausted retries, moved to failed-exhausted"
      fi
    fi

    local remaining=$(( target - elapsed ))
    [ "$remaining" -gt 0 ] && sleep "$remaining"
  done
}

summarize() {
  local done_n failed_n exhausted_n
  done_n=$(find "$DONE_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  failed_n=$(find "$FAILED_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  exhausted_n=$(find "$EXHAUSTED_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  log "summary: done=$done_n failed=$failed_n exhausted=$exhausted_n branch=$BRANCH"
}

main() {
  log "run start: until=$UNTIL max_retries=$MAX_RETRIES"
  setup_worktree
  if primary_phase; then
    secondary_phase || true
  fi
  summarize
  log "run end"
}

main

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

# --- one-time repo prep: not a worktree/branch (that's per-task now) ---
bootstrap_repo() {
  # git worktree add -b needs a real commit to branch from. Some git versions
  # (e.g. 2.39, this container's) do not infer --orphan on an unborn HEAD the
  # way newer git does, and fail outright instead. Bootstrap with an empty
  # commit rather than requiring every fresh repo to have committed first.
  if ! git -C "$PROJECT_ROOT" rev-parse HEAD >/dev/null 2>&1; then
    git -C "$PROJECT_ROOT" commit --allow-empty -m "overnight-queue: bootstrap initial commit" >>"$LOG" 2>&1
  fi
  # Every task's worktree forks from this same commit, captured once, so no
  # task can ever see another task's changes -- true per-task isolation.
  BASE_SHA="$(git -C "$PROJECT_ROOT" rev-parse HEAD)"
  if ! grep -qxF ".worktrees/" "$PROJECT_ROOT/.gitignore" 2>/dev/null; then
    echo ".worktrees/" >> "$PROJECT_ROOT/.gitignore"
  fi
}

# --- per-task worktree + branch lifecycle ---
task_branch_name() {
  # Simplifying assumption: task filenames within one run are unique, so
  # collisions after sanitizing are not handled specially.
  local slug
  slug=$(printf '%s' "${1%.md}" | tr -c 'A-Za-z0-9_.-' '-')
  printf 'overnight-queue/%s/%s' "$RUN_TS" "$slug"
}

setup_task_worktree() {
  local branch="$1"
  # Always tear down any leftover before creating a fresh one -- covers both
  # a normal previous task's worktree and a stale/broken one (e.g. a
  # host-side `git worktree remove` that couldn't fully resolve a worktree
  # whose .git file was written by this container, using an absolute
  # container path). rm -rf plus prune cleans up either case unconditionally.
  if [ -d "$WORKTREE_DIR" ]; then
    git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" >>"$LOG" 2>&1
    rm -rf "$WORKTREE_DIR"
    git -C "$PROJECT_ROOT" worktree prune >>"$LOG" 2>&1
  fi
  git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" -b "$branch" "$BASE_SHA" >>"$LOG" 2>&1
}

teardown_task_worktree() {
  git -C "$PROJECT_ROOT" worktree remove --force "$WORKTREE_DIR" >>"$LOG" 2>&1
  rm -rf "$WORKTREE_DIR"
  git -C "$PROJECT_ROOT" worktree prune >>"$LOG" 2>&1
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
  out="$(cd "$WORKTREE_DIR" && claude --settings /home/node/container-settings.json -p "$prompt" --model haiku --permission-mode bypassPermissions --output-format json 2>&1)"
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
    if ! git -C "$WORKTREE_DIR" commit -q -m "$task_name: completed by overnight-queue" 2>>"$LOG"; then
      log "WARNING: $task_name reported done but commit failed (see error above) -- changes are staged but uncommitted"
    fi
  fi
}

# --- orchestrates one full task attempt: fresh worktree+branch, run, commit
# or discard, always tear the worktree back down. Sets ATTEMPT_OK,
# ATTEMPT_OUTPUT (from run_attempt) and TASK_BRANCH as globals. TASK_BRANCH
# only has surviving commits when ATTEMPT_OK=1 -- a failed attempt's branch
# is deleted since it's identical to $BASE_SHA and holds nothing unique. ---
run_task() {
  local task_name="$1"
  local prompt="$2"

  TASK_BRANCH="$(task_branch_name "$task_name")"
  setup_task_worktree "$TASK_BRANCH"
  run_attempt "$prompt"

  if [ "$ATTEMPT_OK" -eq 1 ]; then
    commit_task "$task_name"
  fi
  teardown_task_worktree
  if [ "$ATTEMPT_OK" -ne 1 ]; then
    git -C "$PROJECT_ROOT" branch -D "$TASK_BRANCH" >>"$LOG" 2>&1
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
    run_task "$task_name" "$(cat "$task")"
    local elapsed=$(( $(now_epoch) - start ))

    if [ "$ATTEMPT_OK" -eq 1 ]; then
      mv "$task" "$DONE_DIR/"
      log "primary: $task_name done ($(extract_usage_summary "$ATTEMPT_OUTPUT"), ${elapsed}s, branch=$TASK_BRANCH)"
    elif looks_rate_limited "$ATTEMPT_OUTPUT"; then
      log "primary: $task_name rate-limited, backing off"
      backoff_then_check_deadline || return 1
      continue
    else
      mv "$task" "$FAILED_DIR/"
      bump_attempt_count "$task"
      log "primary: $task_name failed: $(printf '%s' "$ATTEMPT_OUTPUT" | tail -n5 | tr '\n' ' ')"
    fi

    # Only pace with a sleep if there's still primary work left; otherwise
    # the next loop iteration's "queue empty" check would just be waiting
    # out the clock for no reason.
    local remaining=$(( target - elapsed ))
    local still_pending
    still_pending=$(find "$QUEUE_DIR" -maxdepth 1 -name '*.md' -type f | grep -c . || true)
    if [ "$remaining" -gt 0 ] && [ "$still_pending" -gt 0 ]; then
      sleep "$remaining"
    fi
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
    run_task "$task_name" "$prompt"
    local elapsed=$(( $(now_epoch) - start ))

    if [ "$ATTEMPT_OK" -eq 1 ]; then
      mv "$task" "$DONE_DIR/"
      log "retry: $task_name done ($(extract_usage_summary "$ATTEMPT_OUTPUT"), ${elapsed}s, branch=$TASK_BRANCH)"
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

    # Only pace with a sleep if something retryable is still left; otherwise
    # the next loop iteration's "nothing left retryable" check would just be
    # waiting out the clock for no reason.
    local remaining=$(( target - elapsed ))
    local still_retryable=0
    for f in "$FAILED_DIR"/*.md; do
      [ -e "$f" ] || continue
      [ "$(attempt_count "$f")" -lt "$MAX_RETRIES" ] && still_retryable=1 && break
    done
    if [ "$remaining" -gt 0 ] && [ "$still_retryable" -eq 1 ]; then
      sleep "$remaining"
    fi
  done
}

summarize() {
  local done_n failed_n exhausted_n
  done_n=$(find "$DONE_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  failed_n=$(find "$FAILED_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  exhausted_n=$(find "$EXHAUSTED_DIR" -name '*.md' -type f 2>/dev/null | grep -c . || true)
  log "summary: done=$done_n failed=$failed_n exhausted=$exhausted_n branches=overnight-queue/$RUN_TS/*"
}

main() {
  log "run start: until=$UNTIL max_retries=$MAX_RETRIES"
  bootstrap_repo
  if primary_phase; then
    secondary_phase || true
  fi
  summarize
  log "run end"
}

main

#!/usr/bin/env bash
set -euo pipefail

ORCHESTRATE_TIMEOUT="${ORCHESTRATE_TIMEOUT:-300}"
ORCHESTRATE_WORKERS_DIR="${ORCHESTRATE_WORKERS_DIR:-.workers}"

poll_workers() {
  local results=()
  local now
  now=$(date +%s)

  for task_dir in "$ORCHESTRATE_WORKERS_DIR"/*/; do
    [[ -d "$task_dir" ]] || continue

    local task_id
    task_id=$(basename "$task_dir")
    local status
    status=$(<"$task_dir/status")

    # Skip already completed/failed workers
    if [[ "$status" == "done" || "$status" == "failed" ]]; then
      results+=("{\"task_id\": \"$task_id\", \"status\": \"$status\"}")
      continue
    fi

    local pid
    pid=$(<"$task_dir/pid")

    # Check timeout
    local started_at
    started_at=$(<"$task_dir/started_at")
    local elapsed=$(( now - started_at ))

    if (( elapsed > ORCHESTRATE_TIMEOUT )); then
      kill "$pid" 2>/dev/null || true
      echo "failed" > "$task_dir/status"
      echo "Timeout after ${elapsed}s" >> "$task_dir/output.log"
      results+=("{\"task_id\": \"$task_id\", \"status\": \"failed\", \"reason\": \"timeout\"}")
      continue
    fi

    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
      # Process finished - generate diff
      if [[ -d "$task_dir/tree" ]]; then
        (cd "$task_dir/tree" && git diff HEAD > "../diff.patch" 2>/dev/null) || true
      fi

      # Check if there's meaningful output
      if [[ -s "$task_dir/diff.patch" ]] || [[ -s "$task_dir/output.log" ]]; then
        echo "done" > "$task_dir/status"
        results+=("{\"task_id\": \"$task_id\", \"status\": \"done\"}")
      else
        echo "failed" > "$task_dir/status"
        results+=("{\"task_id\": \"$task_id\", \"status\": \"failed\", \"reason\": \"no output\"}")
      fi
    else
      results+=("{\"task_id\": \"$task_id\", \"status\": \"running\", \"elapsed\": $elapsed}")
    fi
  done

  # Output JSON array
  if [[ ${#results[@]} -eq 0 ]]; then
    echo "[]"
  else
    echo "[$(IFS=,; echo "${results[*]}")]"
  fi
}

poll_workers

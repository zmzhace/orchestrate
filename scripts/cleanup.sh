#!/usr/bin/env bash
set -euo pipefail

ORCHESTRATE_WORKERS_DIR="${ORCHESTRATE_WORKERS_DIR:-.workers}"

cleanup_worker() {
  local task_id="$1"
  local task_dir="$ORCHESTRATE_WORKERS_DIR/$task_id"

  if [[ ! -d "$task_dir" ]]; then
    echo "Worker $task_id not found" >&2
    return 1
  fi

  # Kill process if still running
  if [[ -f "$task_dir/pid" ]]; then
    local pid
    pid=$(<"$task_dir/pid")
    kill "$pid" 2>/dev/null || true
  fi

  # Remove worktree
  if [[ -d "$task_dir/tree" ]]; then
    git worktree remove "$task_dir/tree" --force 2>/dev/null || true
  fi

  # Remove branch
  git branch -D "orchestrate/$task_id" 2>/dev/null || true

  # Remove worker directory
  rm -rf "$task_dir"

  echo "{\"task_id\": \"$task_id\", \"cleaned\": true}"
}

cleanup_all() {
  for task_dir in "$ORCHESTRATE_WORKERS_DIR"/*/; do
    [[ -d "$task_dir" ]] || continue
    local task_id
    task_id=$(basename "$task_dir")
    cleanup_worker "$task_id"
  done
  rmdir "$ORCHESTRATE_WORKERS_DIR" 2>/dev/null || true
}

if [[ "${1:-}" == "--all" ]]; then
  cleanup_all
elif [[ -n "${1:-}" ]]; then
  cleanup_worker "$1"
else
  echo "Usage: cleanup.sh <task_id> | --all" >&2
  exit 1
fi

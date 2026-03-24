#!/usr/bin/env bash
set -euo pipefail

ORCHESTRATE_WORKERS_DIR="${ORCHESTRATE_WORKERS_DIR:-.workers}"

collect_single() {
  local task_id="$1"
  local task_dir="$ORCHESTRATE_WORKERS_DIR/$task_id"

  if [[ ! -d "$task_dir" ]]; then
    echo "{\"error\": \"task $task_id not found\"}" >&2
    return 1
  fi

  local status
  status=$(<"$task_dir/status")
  local diff_lines=0
  local diff_files=0

  if [[ -f "$task_dir/diff.patch" ]]; then
    diff_lines=$(wc -l < "$task_dir/diff.patch" | tr -d ' ')
    diff_files=$(grep -c '^diff --git' "$task_dir/diff.patch" 2>/dev/null || echo "0")
  fi

  cat <<EOF
{"task_id": "$task_id", "status": "$status", "diff_lines": $diff_lines, "diff_files": $diff_files, "diff_path": "$task_dir/diff.patch", "output_path": "$task_dir/output.log", "worktree": "$task_dir/tree"}
EOF
}

collect_all() {
  local results=()
  for task_dir in "$ORCHESTRATE_WORKERS_DIR"/*/; do
    [[ -d "$task_dir" ]] || continue
    local task_id
    task_id=$(basename "$task_dir")
    results+=("$(collect_single "$task_id")")
  done
  if [[ ${#results[@]} -eq 0 ]]; then
    echo "[]"
  else
    echo "[$(IFS=,; echo "${results[*]}")]"
  fi
}

if [[ -n "${1:-}" ]]; then
  collect_single "$1"
else
  collect_all
fi

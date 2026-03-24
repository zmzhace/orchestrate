#!/usr/bin/env bash
set -euo pipefail

ORCHESTRATE_TIMEOUT="${ORCHESTRATE_TIMEOUT:-300}"
ORCHESTRATE_WORKERS_DIR="${ORCHESTRATE_WORKERS_DIR:-.workers}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TEMPLATE_DIR="$SCRIPT_DIR/../templates"

validate_args() {
  if [[ $# -lt 4 ]]; then
    echo "Usage: dispatch.sh <task_id> <description> <scope> <context> [acceptance_criteria]" >&2
    return 1
  fi
}

generate_prompt() {
  local template_file="$1"
  local content
  content=$(<"$template_file")
  content="${content//\{TASK_DESCRIPTION\}/$TASK_DESCRIPTION}"
  content="${content//\{TASK_SCOPE\}/$TASK_SCOPE}"
  content="${content//\{TASK_CONTEXT\}/$TASK_CONTEXT}"
  content="${content//\{TASK_ACCEPTANCE_CRITERIA\}/$TASK_ACCEPTANCE_CRITERIA}"
  echo "$content"
}

dispatch_worker() {
  local task_id="$1"
  local task_dir="$ORCHESTRATE_WORKERS_DIR/$task_id"

  # Create worker directory
  mkdir -p "$task_dir"

  # Create worktree
  git worktree add "$task_dir/tree" -b "orchestrate/$task_id" 2>/dev/null

  # Generate prompt
  generate_prompt "$TEMPLATE_DIR/worker-prompt.md" > "$task_dir/prompt.md"

  # Record start time
  date +%s > "$task_dir/started_at"

  # Launch codex in background
  (
    cd "$task_dir/tree"
    codex --quiet --full-auto \
      --prompt "$(cat "$task_dir/prompt.md")" \
      > "$task_dir/output.log" 2>&1
  ) &

  local pid=$!
  echo "$pid" > "$task_dir/pid"
  echo "running" > "$task_dir/status"

  echo "{\"task_id\": \"$task_id\", \"pid\": $pid, \"status\": \"running\", \"worktree\": \"$task_dir/tree\"}"
}

# Allow sourcing for tests
if [[ "${1:-}" == "--source-only" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Main execution
validate_args "$@"

TASK_ID="$1"
TASK_DESCRIPTION="$2"
TASK_SCOPE="$3"
TASK_CONTEXT="$4"
TASK_ACCEPTANCE_CRITERIA="${5:-No additional criteria}"

export TASK_DESCRIPTION TASK_SCOPE TASK_CONTEXT TASK_ACCEPTANCE_CRITERIA

dispatch_worker "$TASK_ID"

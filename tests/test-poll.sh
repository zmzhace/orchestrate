#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKERS_DIR=$(mktemp -d)

# Setup: fake a completed worker (PID that doesn't exist)
mkdir -p "$WORKERS_DIR/test-task"
echo "running" > "$WORKERS_DIR/test-task/status"
echo "99999" > "$WORKERS_DIR/test-task/pid"
date +%s > "$WORKERS_DIR/test-task/started_at"
mkdir -p "$WORKERS_DIR/test-task/tree"
echo "some output" > "$WORKERS_DIR/test-task/output.log"

echo "Test 1: detect completed worker"
result=$(ORCHESTRATE_WORKERS_DIR="$WORKERS_DIR" bash "$PROJECT_DIR/scripts/poll.sh")
if echo "$result" | grep -q '"done"\|"failed"'; then
  echo "PASS"
else
  echo "FAIL: worker should be detected as done or failed"
  echo "$result"
  exit 1
fi

# Test 2: already-done worker stays done
echo "done" > "$WORKERS_DIR/test-task/status"
echo "Test 2: already-done worker reported correctly"
result=$(ORCHESTRATE_WORKERS_DIR="$WORKERS_DIR" bash "$PROJECT_DIR/scripts/poll.sh")
if echo "$result" | grep -q '"done"'; then
  echo "PASS"
else
  echo "FAIL: done worker should stay done"
  echo "$result"
  exit 1
fi

# Test 3: empty workers dir returns empty array
EMPTY_DIR=$(mktemp -d)
echo "Test 3: empty workers dir"
result=$(ORCHESTRATE_WORKERS_DIR="$EMPTY_DIR" bash "$PROJECT_DIR/scripts/poll.sh")
if [[ "$result" == "[]" ]]; then
  echo "PASS"
else
  echo "FAIL: expected empty array"
  echo "$result"
  exit 1
fi

# Cleanup
rm -rf "$WORKERS_DIR" "$EMPTY_DIR"
echo "All poll tests passed"

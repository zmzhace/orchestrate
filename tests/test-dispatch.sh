#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Test 1: validate_args should fail with no arguments
echo "Test 1: validate_args with no args"
source "$PROJECT_DIR/scripts/dispatch.sh" --source-only
if validate_args 2>/dev/null; then
  echo "FAIL: should have failed with no args"
  exit 1
fi
echo "PASS"

# Test 2: generate_prompt should substitute placeholders
echo "Test 2: generate_prompt substitution"
TASK_DESCRIPTION="Add logging"
TASK_SCOPE="src/api/"
TASK_CONTEXT="Express app"
TASK_ACCEPTANCE_CRITERIA="All endpoints log requests"
export TASK_DESCRIPTION TASK_SCOPE TASK_CONTEXT TASK_ACCEPTANCE_CRITERIA
result=$(generate_prompt "$PROJECT_DIR/templates/worker-prompt.md")
if [[ "$result" != *"Add logging"* ]]; then
  echo "FAIL: description not substituted"
  exit 1
fi
if [[ "$result" != *"src/api/"* ]]; then
  echo "FAIL: scope not substituted"
  exit 1
fi
if [[ "$result" != *"Express app"* ]]; then
  echo "FAIL: context not substituted"
  exit 1
fi
if [[ "$result" != *"All endpoints log requests"* ]]; then
  echo "FAIL: acceptance_criteria not substituted"
  exit 1
fi
echo "PASS"

# Test 3: validate_args should succeed with 4 args
echo "Test 3: validate_args with 4 args"
if ! validate_args "id" "desc" "scope" "ctx"; then
  echo "FAIL: should have succeeded with 4 args"
  exit 1
fi
echo "PASS"

echo "All dispatch tests passed"

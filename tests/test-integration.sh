#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

# Create a temp directory for the test
TEST_DIR=$(mktemp -d)
trap "rm -rf '$TEST_DIR'" EXIT

# Setup: create a temp git repo
cd "$TEST_DIR"
git init
git config user.email "test@test.com"
git config user.name "Test"
echo "hello" > file.txt
git add . && git commit -m "init"

# Create a fake codex that modifies a file and commits
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/codex" << 'MOCK'
#!/usr/bin/env bash
# Mock codex: modify file.txt and commit
# Accepts and ignores any flags (--quiet, --full-auto, --prompt, etc.)
echo "modified by codex" > file.txt
git add -A
git commit -m "codex: modified file" --allow-empty
echo "Mock codex completed successfully"
MOCK
chmod +x "$TEST_DIR/bin/codex"
export PATH="$TEST_DIR/bin:$PATH"

export ORCHESTRATE_WORKERS_DIR="$TEST_DIR/.workers"
export ORCHESTRATE_TIMEOUT=30

echo "=== Test 1: dispatch ==="
result=$(bash "$PROJECT_DIR/scripts/dispatch.sh" "test-1" "modify file.txt" "file.txt" "test context" "file should say modified")
echo "$result"
if echo "$result" | grep -q '"status": "running"'; then
  echo "PASS: worker dispatched"
else
  echo "FAIL: dispatch didn't return running status"
  exit 1
fi

# Wait for mock codex to finish
sleep 3

echo "=== Test 2: poll ==="
result=$(bash "$PROJECT_DIR/scripts/poll.sh")
echo "$result"
if echo "$result" | grep -q '"done"\|"failed"'; then
  echo "PASS: worker detected as finished"
else
  echo "FAIL: worker still running or not detected"
  exit 1
fi

echo "=== Test 3: collect ==="
result=$(bash "$PROJECT_DIR/scripts/collect.sh" "test-1")
echo "$result"
if echo "$result" | grep -q '"task_id": "test-1"'; then
  echo "PASS: results collected"
else
  echo "FAIL: collection failed"
  exit 1
fi

echo "=== Test 4: cleanup ==="
bash "$PROJECT_DIR/scripts/cleanup.sh" --all
if [[ ! -d "$TEST_DIR/.workers/test-1" ]]; then
  echo "PASS: worker cleaned up"
else
  echo "FAIL: worker directory still exists"
  exit 1
fi

echo ""
echo "=== All integration tests passed ==="

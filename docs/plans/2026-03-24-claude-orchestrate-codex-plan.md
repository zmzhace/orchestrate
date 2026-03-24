# Claude Orchestrate Codex - Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Claude Code skill + shell scripts system that lets Claude automatically dispatch coding subtasks to Codex CLI workers in isolated git worktrees, review results, and merge approved changes.

**Architecture:** A Claude Code skill defines orchestration logic (when to activate, how to decompose tasks, how to review). Shell scripts handle mechanical operations (worktree lifecycle, Codex process management, result collection). Runtime state is tracked in `.workers/` directory with simple files (status, pid, logs, patches).

**Tech Stack:** Bash scripts, Git worktrees, Codex CLI (`@openai/codex`), Claude Code skill format (Markdown)

---

### Task 1: Initialize Git Repository and Project Structure

**Files:**
- Create: `scripts/dispatch.sh`
- Create: `scripts/poll.sh`
- Create: `scripts/collect.sh`
- Create: `scripts/cleanup.sh`
- Create: `templates/worker-prompt.md`
- Create: `skill.md`
- Create: `.gitignore`

**Step 1: Initialize git repo**

```bash
cd /Users/Zhuanz/orchestrate
git init
```

**Step 2: Create .gitignore**

```gitignore
.workers/
.omc/
```

**Step 3: Create directory structure**

```bash
mkdir -p scripts templates
```

**Step 4: Create placeholder files**

```bash
touch scripts/dispatch.sh scripts/poll.sh scripts/collect.sh scripts/cleanup.sh
touch templates/worker-prompt.md skill.md
chmod +x scripts/*.sh
```

**Step 5: Commit**

```bash
git add .gitignore scripts/ templates/ skill.md docs/
git commit -m "chore: initialize project structure"
```

---

### Task 2: Worker Prompt Template

**Files:**
- Create: `templates/worker-prompt.md`

**Step 1: Write the prompt template**

```markdown
You are a focused coding worker. Complete the following task precisely.

## Task
{TASK_DESCRIPTION}

## Scope
You may ONLY modify files within:
{TASK_SCOPE}

## Context
{TASK_CONTEXT}

## Acceptance Criteria
When complete, ensure:
{TASK_ACCEPTANCE_CRITERIA}

## Rules
- Do NOT modify files outside the specified scope
- Do NOT install new dependencies unless the task explicitly requires it
- Keep changes minimal and focused
- Commit your changes with a clear message before finishing
```

**Step 2: Commit**

```bash
git add templates/worker-prompt.md
git commit -m "feat: add worker prompt template"
```

---

### Task 3: dispatch.sh - Create Worktree and Launch Codex Worker

**Files:**
- Create: `scripts/dispatch.sh`
- Test: manual verification with mock

**Step 1: Write a test script to verify dispatch behavior**

Create `tests/test-dispatch.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
source "$SCRIPT_DIR/scripts/dispatch.sh" --source-only 2>/dev/null || true

# Test: validate_args should fail with no arguments
echo "Test 1: validate_args with no args"
if validate_args 2>/dev/null; then
  echo "FAIL: should have failed with no args"
  exit 1
fi
echo "PASS"

# Test: generate_prompt should substitute placeholders
echo "Test 2: generate_prompt substitution"
TASK_DESCRIPTION="Add logging"
TASK_SCOPE="src/api/"
TASK_CONTEXT="Express app"
TASK_ACCEPTANCE_CRITERIA="All endpoints log requests"
result=$(generate_prompt "$SCRIPT_DIR/templates/worker-prompt.md")
if [[ "$result" != *"Add logging"* ]]; then
  echo "FAIL: description not substituted"
  exit 1
fi
if [[ "$result" != *"src/api/"* ]]; then
  echo "FAIL: scope not substituted"
  exit 1
fi
echo "PASS"

echo "All dispatch tests passed"
```

**Step 2: Run test to verify it fails**

```bash
chmod +x tests/test-dispatch.sh
bash tests/test-dispatch.sh
```

Expected: FAIL (functions not defined yet)

**Step 3: Write dispatch.sh**

```bash
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
```

**Step 4: Run test to verify it passes**

```bash
bash tests/test-dispatch.sh
```

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/dispatch.sh tests/test-dispatch.sh
git commit -m "feat: implement dispatch.sh for worktree creation and codex launch"
```

---

### Task 4: poll.sh - Check Worker Status

**Files:**
- Create: `scripts/poll.sh`
- Test: `tests/test-poll.sh`

**Step 1: Write test**

Create `tests/test-poll.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORKERS_DIR=$(mktemp -d)

# Setup: fake a completed worker
mkdir -p "$WORKERS_DIR/test-task"
echo "running" > "$WORKERS_DIR/test-task/status"
# Use a PID that doesn't exist (completed process)
echo "99999" > "$WORKERS_DIR/test-task/pid"
date +%s > "$WORKERS_DIR/test-task/started_at"
mkdir -p "$WORKERS_DIR/test-task/tree"

echo "Test 1: detect completed worker"
ORCHESTRATE_WORKERS_DIR="$WORKERS_DIR" bash "$SCRIPT_DIR/scripts/poll.sh" > /tmp/poll-result.json
if grep -q '"done"\|"failed"' /tmp/poll-result.json; then
  echo "PASS"
else
  echo "FAIL: worker should be detected as done or failed"
  cat /tmp/poll-result.json
  exit 1
fi

# Cleanup
rm -rf "$WORKERS_DIR"
echo "All poll tests passed"
```

**Step 2: Run test to verify it fails**

```bash
chmod +x tests/test-poll.sh
bash tests/test-poll.sh
```

Expected: FAIL

**Step 3: Write poll.sh**

```bash
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
      if [[ -d "$task_dir/tree/.git" || -d "$task_dir/tree" ]]; then
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
  echo "[$(IFS=,; echo "${results[*]:-}")]"
}

poll_workers
```

**Step 4: Run test to verify it passes**

```bash
bash tests/test-poll.sh
```

Expected: PASS

**Step 5: Commit**

```bash
git add scripts/poll.sh tests/test-poll.sh
git commit -m "feat: implement poll.sh for worker status checking"
```

---

### Task 5: collect.sh - Collect Worker Results

**Files:**
- Create: `scripts/collect.sh`

**Step 1: Write collect.sh**

```bash
#!/usr/bin/env bash
set -euo pipefail

ORCHESTRATE_WORKERS_DIR="${ORCHESTRATE_WORKERS_DIR:-.workers}"

# Collect results for a specific task or all tasks
collect_results() {
  local task_id="${1:-}"

  if [[ -n "$task_id" ]]; then
    collect_single "$task_id"
  else
    collect_all
  fi
}

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
  local diff_files=""

  if [[ -f "$task_dir/diff.patch" ]]; then
    diff_lines=$(wc -l < "$task_dir/diff.patch" | tr -d ' ')
    diff_files=$(grep -c '^diff --git' "$task_dir/diff.patch" 2>/dev/null || echo "0")
  fi

  cat <<EOF
{
  "task_id": "$task_id",
  "status": "$status",
  "diff_lines": $diff_lines,
  "diff_files": $diff_files,
  "diff_path": "$task_dir/diff.patch",
  "output_path": "$task_dir/output.log",
  "worktree": "$task_dir/tree"
}
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
  echo "[$(IFS=,; echo "${results[*]:-}")]"
}

collect_results "${1:-}"
```

**Step 2: Commit**

```bash
git add scripts/collect.sh
git commit -m "feat: implement collect.sh for gathering worker results"
```

---

### Task 6: cleanup.sh - Clean Up Worktrees

**Files:**
- Create: `scripts/cleanup.sh`

**Step 1: Write cleanup.sh**

```bash
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
```

**Step 2: Commit**

```bash
git add scripts/cleanup.sh
git commit -m "feat: implement cleanup.sh for worktree removal"
```

---

### Task 7: skill.md - Claude Code Skill Definition

**Files:**
- Create: `skill.md`

**Step 1: Write the skill definition**

This is the core — it teaches Claude when and how to orchestrate Codex workers.

```markdown
---
name: orchestrate
description: Automatically dispatch coding subtasks to Codex CLI workers in isolated git worktrees, review results, and merge approved changes
---

## When to Activate

Activate this skill when ALL of the following are true:
- The task involves modifications to 2+ independent files or modules
- The subtasks do NOT depend on each other's output
- Each subtask is self-contained enough for Codex to complete without cross-file reasoning

Do NOT activate when:
- Task is a single-file change
- Task requires deep architectural reasoning across modules
- Task requires frequent user interaction or clarification

## Orchestration Process

### Step 1: Decompose the Task

Analyze the user's request and split it into independent subtasks. For each subtask, define:
- `task_id`: short kebab-case identifier (e.g., `add-logging-users-api`)
- `description`: clear, self-contained instruction for Codex
- `scope`: exact file paths or directories Codex may modify
- `context`: relevant code snippets, interfaces, patterns to follow
- `acceptance_criteria`: what "done" looks like

Tell the user: "I'm splitting this into N parallel tasks and dispatching to workers."

### Step 2: Dispatch Workers

For each subtask, run:
```bash
bash scripts/dispatch.sh "{task_id}" "{description}" "{scope}" "{context}" "{acceptance_criteria}"
```

All dispatches can run in parallel.

### Step 3: Monitor Progress

Poll worker status periodically:
```bash
bash scripts/poll.sh
```

Report progress to user: "3/5 workers complete, 2 still running..."

### Step 4: Collect and Review Results

Once all workers are done:
```bash
bash scripts/collect.sh
```

For each completed worker:
1. Read the diff: `cat .workers/{task_id}/diff.patch`
2. Read the log: `cat .workers/{task_id}/output.log`
3. Review against acceptance_criteria
4. Check for: bugs, security issues, scope violations, style consistency

### Step 5: Merge Approved Changes

For each approved worker:
```bash
cd .workers/{task_id}/tree
git add -A && git commit -m "orchestrate: {description}"
cd -
git merge orchestrate/{task_id} --no-ff -m "merge: orchestrate/{task_id}"
```

Merge smallest changes first to minimize conflicts. Resolve conflicts yourself if they arise.

For rejected workers: either fix the issues yourself or re-dispatch to Codex with more specific instructions.

### Step 6: Cleanup

```bash
bash scripts/cleanup.sh --all
```

Report final results to user.

## Important Rules

- ALWAYS create worktrees — never let Codex modify the main working tree
- ALWAYS review diffs before merging — Codex output is not trusted by default
- If a worker fails or produces bad output, handle it yourself rather than blocking the user
- Keep the user informed of progress but don't overwhelm with details
```

**Step 2: Commit**

```bash
git add skill.md
git commit -m "feat: add Claude Code skill definition for orchestrating Codex workers"
```

---

### Task 8: Integration Test - End to End

**Files:**
- Create: `tests/test-integration.sh`

**Step 1: Write integration test**

This test verifies the full dispatch → poll → collect → cleanup cycle using a mock codex command.

```bash
#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_DIR=$(mktemp -d)
export ORCHESTRATE_WORKERS_DIR="$TEST_DIR/.workers"
export ORCHESTRATE_TIMEOUT=10

# Setup: create a temp git repo
cd "$TEST_DIR"
git init
echo "hello" > file.txt
git add . && git commit -m "init"

# Create a fake codex that just modifies a file
mkdir -p "$TEST_DIR/bin"
cat > "$TEST_DIR/bin/codex" << 'MOCK'
#!/usr/bin/env bash
# Mock codex: just modify file.txt
echo "modified by codex" > file.txt
git add -A && git commit -m "codex: modified file"
MOCK
chmod +x "$TEST_DIR/bin/codex"
export PATH="$TEST_DIR/bin:$PATH"

echo "=== Test: dispatch ==="
bash "$SCRIPT_DIR/scripts/dispatch.sh" "test-1" "modify file.txt" "file.txt" "test context"
sleep 2

echo "=== Test: poll ==="
bash "$SCRIPT_DIR/scripts/poll.sh"

echo "=== Test: collect ==="
bash "$SCRIPT_DIR/scripts/collect.sh"

echo "=== Test: cleanup ==="
bash "$SCRIPT_DIR/scripts/cleanup.sh" --all

echo "=== All integration tests passed ==="

# Cleanup temp dir
rm -rf "$TEST_DIR"
```

**Step 2: Run integration test**

```bash
chmod +x tests/test-integration.sh
bash tests/test-integration.sh
```

**Step 3: Commit**

```bash
git add tests/test-integration.sh
git commit -m "test: add integration test with mock codex"
```

---

### Task 9: Installation Script

**Files:**
- Create: `install.sh`

**Step 1: Write install script**

```bash
#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Installing Claude Orchestrate Codex..."

# Check prerequisites
if ! command -v codex &>/dev/null; then
  echo "Warning: codex CLI not found. Install with: npm install -g @openai/codex"
fi

if ! command -v git &>/dev/null; then
  echo "Error: git is required" >&2
  exit 1
fi

# Make scripts executable
chmod +x "$INSTALL_DIR/scripts/"*.sh

# Print skill registration instructions
echo ""
echo "Installation complete!"
echo ""
echo "To use, register the skill in your Claude Code settings:"
echo "  Add '$INSTALL_DIR/skill.md' to your skills directory"
echo ""
echo "Or copy skill.md to your project's .claude/skills/ directory:"
echo "  mkdir -p .claude/skills && cp $INSTALL_DIR/skill.md .claude/skills/orchestrate.md"
```

**Step 2: Commit**

```bash
git add install.sh
chmod +x install.sh
git commit -m "feat: add installation script"
```

---

### Task 10: Final Review and README

**Files:**
- Verify all scripts are executable
- Run full test suite
- Verify skill.md is complete

**Step 1: Run all tests**

```bash
bash tests/test-dispatch.sh
bash tests/test-poll.sh
bash tests/test-integration.sh
```

**Step 2: Final commit**

```bash
git add -A
git commit -m "chore: finalize project structure and verify all tests pass"
```

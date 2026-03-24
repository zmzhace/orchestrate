# Claude Orchestrate Codex - Design Document

> Date: 2026-03-24

## Overview

A Claude Code skill + shell scripts system that enables Claude Code CLI to automatically dispatch coding subtasks to OpenAI Codex CLI workers running in isolated git worktrees, then review and merge the results.

## Requirements

- Claude Code CLI as orchestrator, Codex CLI as worker
- User-transparent: Claude auto-decides what to delegate, user sees progress only
- Each Codex worker runs in an isolated git worktree
- Claude reviews diffs and merges approved changes
- Unlimited parallel workers
- Delivered as a Claude Code skill + shell scripts, zero external dependencies

## Architecture

```
User -> Claude Code (skill activated)
         |
         +-- Analyze task, determine if splittable
         |
         +-- Decompose into N independent subtasks
         |
         +-- For each subtask:
         |     dispatch.sh -> git worktree create -> codex CLI execute -> output result
         |
         +-- Collect all worker results (poll.sh + collect.sh)
         |
         +-- Review each worktree's diff
         |
         +-- Merge approved changes -> cleanup worktrees (cleanup.sh)
```

## Project Structure

```
orchestrate/
├── skill.md              # Claude Code skill definition
├── scripts/
│   ├── dispatch.sh       # Create worktree + start codex worker
│   ├── poll.sh           # Check worker completion status
│   ├── collect.sh        # Collect worker diff results
│   └── cleanup.sh        # Clean up worktrees
├── templates/
│   └── worker-prompt.md  # Prompt template for Codex
└── .workers/             # Runtime directory for worker state
    └── {task-id}/
        ├── status        # pending|running|done|failed
        ├── prompt.md     # Actual prompt sent to codex
        ├── output.log    # codex stdout/stderr
        └── diff.patch    # Change patch
```

## Skill Trigger Logic

**Activate when:**
- Task involves modifications to multiple independent files/modules
- Task can be split into non-dependent subtasks
- Each subtask's complexity is suitable for Codex to complete independently

**Do not activate when:**
- Simple single-file modification
- Deep cross-module reasoning required
- Frequent user interaction needed

## Task Decomposition

Claude generates for each subtask:
- `task_id`: unique identifier
- `description`: natural language description for Codex
- `scope`: file/directory restriction for Codex
- `context`: background info (code snippets, interface definitions)
- `acceptance_criteria`: review criteria for Claude

## Worker Prompt Template

```
You are a focused coding worker. Your task:
{description}

You may only modify files within:
{scope}

Background:
{context}

When complete, ensure:
{acceptance_criteria}
```

## Worker Execution (dispatch.sh)

1. `git worktree add .workers/{task_id}/tree -b orchestrate/{task_id}`
2. Write prompt to worker directory
3. Run `codex --quiet --full-auto --prompt "$(cat prompt.md)"` in background
4. Record PID and set status to "running"

## Polling (poll.sh)

- Iterate all workers, check if process is alive via `kill -0`
- On completion: check exit code, generate diff.patch, update status
- Timeout: default 300s, kill process and mark failed if exceeded
- Output summary in JSON format for Claude to consume

## Review & Merge

Claude reviews each worker result:
1. Read diff.patch - check changes
2. Read output.log - check Codex execution process
3. Verify against acceptance_criteria, check for bugs/security issues, verify scope compliance
4. Decision: approve / reject / needs modification

Merge strategy:
- Approved workers: commit in worktree, merge to main with `--no-ff`
- Merge order: smallest changes first to reduce conflict probability
- Conflicts: Claude resolves directly
- Failed workers: Claude checks logs, decides retry or self-complete

## Cleanup (cleanup.sh)

- `git worktree remove .workers/{task_id}/tree`
- `git branch -d orchestrate/{task_id}`
- `rm -rf .workers/{task_id}`

## Configuration

- `ORCHESTRATE_TIMEOUT`: worker timeout, default 300s
- `ORCHESTRATE_WORKERS_DIR`: worker directory, default `.workers/`

## User Experience

User sees only:
1. Claude announces task decomposition and worker dispatch
2. Periodic progress updates (N/M complete)
3. Review results summary (pass/fail per worker)
4. Final completion message

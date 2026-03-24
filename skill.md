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
- The repository has no git history (need at least one commit)

## Orchestration Process

### Step 1: Analyze and Decompose

Analyze the user's request. Identify independent subtasks. For each subtask define:
- **task_id**: short kebab-case identifier (e.g., `add-logging-users-api`)
- **description**: clear, self-contained instruction for Codex — include enough context that Codex can work without seeing other files
- **scope**: exact file paths or directories Codex may modify
- **context**: relevant code snippets, interfaces, type definitions, patterns to follow
- **acceptance_criteria**: what "done" looks like — be specific

Tell the user:
> I'm splitting this into N parallel tasks and dispatching to Codex workers.

List the subtasks briefly so the user knows what's happening.

### Step 2: Dispatch Workers

For each subtask, run dispatch.sh. The script path is relative to this skill file's directory:

```bash
SCRIPT_DIR="$(dirname "SKILL_FILE_PATH")"
bash "$SCRIPT_DIR/scripts/dispatch.sh" "{task_id}" "{description}" "{scope}" "{context}" "{acceptance_criteria}"
```

Replace SKILL_FILE_PATH with the actual path to this skill file at runtime.

All dispatches should be run sequentially (each creates a git branch, parallel creation can conflict).

After all dispatches, tell the user how many workers are running.

### Step 3: Monitor Progress

Poll worker status periodically:

```bash
bash "$SCRIPT_DIR/scripts/poll.sh"
```

Parse the JSON output. Report progress to user:
> Progress: 3/5 workers complete, 2 still running...

Keep polling until all workers are done or failed. Wait a few seconds between polls.

### Step 4: Collect and Review Results

Once all workers are done or failed:

```bash
bash "$SCRIPT_DIR/scripts/collect.sh"
```

For each completed worker, review the changes:

1. **Read the diff**: `cat .workers/{task_id}/diff.patch`
2. **Read the log**: `cat .workers/{task_id}/output.log`
3. **Review against acceptance_criteria**:
   - Does the change fulfill the task description?
   - Are there any bugs or security issues?
   - Did Codex stay within the specified scope?
   - Is the code style consistent with the rest of the project?

For each worker, decide: **approve**, **reject**, or **needs fixing**.

### Step 5: Merge Approved Changes

For each approved worker, merge its changes:

```bash
cd .workers/{task_id}/tree
git add -A
git commit -m "orchestrate: {short description of what was done}"
cd -  # back to project root
git merge orchestrate/{task_id} --no-ff -m "merge: orchestrate/{task_id}"
```

**Merge order**: merge smallest changes first to minimize conflict probability.

**If merge conflicts occur**: resolve them yourself. You have full context of what each worker did.

For rejected workers:
- If the issue is small, fix it yourself directly
- If the issue is large, re-dispatch to Codex with more specific instructions

### Step 6: Cleanup

After all merges are complete:

```bash
bash "$SCRIPT_DIR/scripts/cleanup.sh" --all
```

Report final results to user:
> All done! Here's what was completed:
> - ✓ task-1: description (merged)
> - ✓ task-2: description (merged)
> - ✗ task-3: description (failed, fixed manually)

### Error Handling

- **Worker timeout**: poll.sh handles this automatically (default 300s). If a worker times out, handle its task yourself.
- **Worker produces bad output**: Review the output.log for clues, then handle the task yourself.
- **All workers fail**: Fall back to doing the work yourself. Don't block the user.
- **Git conflicts during merge**: Resolve them. You have context from all workers.

### Environment Variables

- `ORCHESTRATE_TIMEOUT`: Worker timeout in seconds (default: 300)
- `ORCHESTRATE_WORKERS_DIR`: Worker state directory (default: `.workers`)

## Important Rules

1. **ALWAYS use worktrees** — never let Codex modify the main working tree
2. **ALWAYS review diffs before merging** — Codex output is not trusted by default
3. **ALWAYS clean up** — don't leave worktrees and branches behind
4. **If something fails, handle it yourself** — don't block the user waiting for fixes
5. **Keep the user informed** — brief progress updates, not walls of text
6. **Respect .gitignore** — workers dir should be gitignored (it is)

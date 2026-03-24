# Orchestrate

Automatically dispatch coding subtasks to [Codex CLI](https://github.com/openai/codex) workers in isolated git worktrees, review results, and merge approved changes.

## How It Works

```
┌─────────────┐     ┌──────────────┐     ┌──────────────┐
│  Claude Code │────▶│  dispatch.sh │────▶│ Codex Worker │ (worktree A)
│  (orchestor) │     └──────────────┘     └──────────────┘
│              │     ┌──────────────┐     ┌──────────────┐
│              │────▶│  dispatch.sh │────▶│ Codex Worker │ (worktree B)
│              │     └──────────────┘     └──────────────┘
│              │     ┌──────────────┐     ┌──────────────┐
│              │────▶│  dispatch.sh │────▶│ Codex Worker │ (worktree C)
│              │     └──────────────┘     └──────────────┘
│              │                                 │
│              │◀──── poll.sh ◀── collect.sh ◀───┘
│              │
│              │────▶ review & merge ────▶ cleanup.sh
└─────────────┘
```

1. **Decompose** - Claude Code splits a task into independent subtasks
2. **Dispatch** - Each subtask is sent to a Codex worker in an isolated git worktree
3. **Poll** - Monitor worker progress until all complete
4. **Review** - Inspect diffs and logs, approve/reject each result
5. **Merge** - Approved changes are merged back into the main branch
6. **Cleanup** - Worktrees and branches are removed

## Prerequisites

- [Git](https://git-scm.com/)
- [Codex CLI](https://github.com/openai/codex) (`npm install -g @openai/codex`)
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code)

## Installation

```bash
git clone https://github.com/zmzhace/orchestrate.git
cd orchestrate
bash install.sh
```

Then register the skill in your project:

```bash
# Copy skill file
mkdir -p .claude/skills && cp /path/to/orchestrate/skill.md .claude/skills/orchestrate.md

# Or symlink for easy updates
mkdir -p .claude/skills && ln -sf /path/to/orchestrate/skill.md .claude/skills/orchestrate.md
```

Make sure `.workers/` is in your `.gitignore`:

```bash
echo '.workers/' >> .gitignore
```

## Scripts

| Script | Description |
|--------|-------------|
| `scripts/dispatch.sh` | Create a worktree, generate a prompt, and launch a Codex worker |
| `scripts/poll.sh` | Check status of all running workers (JSON output) |
| `scripts/collect.sh` | Gather diffs and logs from completed workers |
| `scripts/cleanup.sh` | Remove worktrees and branches (`--all` or by task ID) |

### dispatch.sh

```bash
bash scripts/dispatch.sh <task_id> <description> <scope> <context> [acceptance_criteria]
```

### poll.sh

```bash
bash scripts/poll.sh
# [{"task_id": "my-task", "status": "running", "elapsed": 12}, ...]
```

### cleanup.sh

```bash
bash scripts/cleanup.sh --all        # Clean all workers
bash scripts/cleanup.sh <task_id>    # Clean specific worker
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `ORCHESTRATE_TIMEOUT` | `300` | Worker timeout in seconds |
| `ORCHESTRATE_WORKERS_DIR` | `.workers` | Worker state directory |

## When to Use

This skill activates when:
- The task involves modifications to 2+ independent files or modules
- The subtasks do NOT depend on each other's output
- Each subtask is self-contained enough for Codex to complete independently

## License

MIT

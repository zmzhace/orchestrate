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
echo "To use, copy the skill to your project's .claude/skills/ directory:"
echo ""
echo "  mkdir -p .claude/skills && cp $INSTALL_DIR/skill.md .claude/skills/orchestrate.md"
echo ""
echo "Or symlink it for easy updates:"
echo ""
echo "  mkdir -p .claude/skills && ln -sf $INSTALL_DIR/skill.md .claude/skills/orchestrate.md"
echo ""
echo "Make sure .workers/ is in your project's .gitignore:"
echo ""
echo "  echo '.workers/' >> .gitignore"

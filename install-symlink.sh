#!/usr/bin/env bash
# Install Chief Wiggum to ~/.claude/chief-wiggum using symlinks
# Useful for development - changes to source files take effect immediately

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${HOME}/.claude/chief-wiggum"

echo "Installing Chief Wiggum to $TARGET (symlink mode)"

# Remove existing installation if present
if [[ -e "$TARGET" ]]; then
    echo "Removing existing installation at $TARGET"
    rm -rf "$TARGET"
fi

# Create parent directory if needed
mkdir -p "$(dirname "$TARGET")"

# Create symlink to source directory
ln -s "$SCRIPT_DIR" "$TARGET"

echo ""
echo "Symlinked $SCRIPT_DIR -> $TARGET"
echo ""
echo "Next steps:"
echo "  1. Add $TARGET/bin to your PATH:"
echo "     echo 'export PATH=\"\$HOME/.claude/chief-wiggum/bin:\$PATH\"' >> ~/.bashrc"
echo "     source ~/.bashrc"
echo ""
echo "  2. Navigate to a project and initialize:"
echo "     cd /path/to/your/project"
echo "     wiggum init"
echo ""
echo "  3. Edit .ralph/kanban.md to add your tasks"
echo ""
echo "  4. Run wiggum to start workers:"
echo "     wiggum run"
echo ""

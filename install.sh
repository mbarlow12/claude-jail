#!/bin/bash
# install.sh - Install claude-jail oh-my-zsh plugin

set -euo pipefail

PLUGIN_NAME="claude-jail"
OMZ_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
PLUGIN_DIR="$OMZ_CUSTOM/plugins/$PLUGIN_NAME"

echo "Installing $PLUGIN_NAME plugin..."

if [[ ! -d "$OMZ_CUSTOM" ]]; then
    echo "Error: Oh My Zsh custom directory not found at $OMZ_CUSTOM" >&2
    echo "Make sure Oh My Zsh is installed." >&2
    exit 1
fi

mkdir -p "$PLUGIN_DIR"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/$PLUGIN_NAME.plugin.zsh" "$PLUGIN_DIR/"

echo "✅ Plugin installed to $PLUGIN_DIR"
echo ""
echo "To enable the plugin, add '$PLUGIN_NAME' to your plugins array in ~/.zshrc:"
echo ""
echo "    plugins=("
echo "        git"
echo "        $PLUGIN_NAME"
echo "        # ... other plugins"
echo "    )"
echo ""
echo "Then reload your shell:"
echo "    source ~/.zshrc"
echo ""
echo "Usage:"
echo "    claude-jail              # Run claude in sandboxed current directory"
echo "    claude-jail -d ~/project # Run claude in sandboxed specific directory"
echo "    claude-jail-shell        # Open a shell in the sandbox (for testing)"
echo "    claude-jail-clean        # Remove .claude-sandbox directory"

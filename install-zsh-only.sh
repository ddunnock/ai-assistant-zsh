#!/usr/bin/env bash
# Quick ZSH integration installer
set -euo pipefail

echo "Installing AI Shell ZSH Integration..."
echo ""

# Create directory
mkdir -p ~/.zsh/ai-shell

# Copy plugin file
cp "$(dirname "$0")/zsh/ai-assistant.zsh" ~/.zsh/ai-shell/ai-assistant.zsh
chmod +x ~/.zsh/ai-shell/ai-assistant.zsh

echo "✓ Installed plugin to ~/.zsh/ai-shell/"
echo ""

# Add to .zshrc if not already present
if [[ -f ~/.zshrc ]] && ! grep -q "ai-assistant.zsh" ~/.zshrc; then
    echo "" >> ~/.zshrc
    echo "# AI Shell Assistant" >> ~/.zshrc
    echo "source ~/.zsh/ai-shell/ai-assistant.zsh" >> ~/.zshrc
    echo "✓ Added to ~/.zshrc"
else
    echo "ℹ Already in ~/.zshrc or ~/.zshrc doesn't exist"
fi

echo ""
echo "Now run:"
echo "  source ~/.zshrc"
echo ""
echo "Then test with:"
echo "  ai_shell_health"

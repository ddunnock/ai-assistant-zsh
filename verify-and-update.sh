#!/bin/bash
# Verification and update script for AI Shell Assistant

echo "=== AI Shell Assistant - Verification and Update ==="
echo ""

# Check if ZSH script is installed
INSTALLED_PATH="$HOME/.zsh/ai-shell/ai-assistant.zsh"

if [[ ! -f "$INSTALLED_PATH" ]]; then
    echo "❌ ZSH script not found at $INSTALLED_PATH"
    echo "   Run ./install-zsh-only.sh to install"
    exit 1
fi

# Check which version is installed
ECHO_COUNT=$(grep -c 'echo "$response" | jq' "$INSTALLED_PATH" 2>/dev/null || echo "0")
PRINTF_COUNT=$(grep -c "printf '%s" "$INSTALLED_PATH" 2>/dev/null || echo "0")

echo "Installed version check:"
echo "  - Old 'echo' pattern instances: $ECHO_COUNT"
echo "  - New 'printf' pattern instances: $PRINTF_COUNT"
echo ""

if [[ $PRINTF_COUNT -ge 20 ]]; then
    echo "✅ You have the latest version installed (printf fix applied)"
    echo ""
    echo "Your ai_shell_task should now work correctly."
    echo ""
    echo "If you're still in the same shell session, run:"
    echo "  exec zsh"
    echo ""
    echo "Then test with:"
    echo "  ai_shell_task \"find all Swift files modified in the last week\""
    exit 0
else
    echo "⚠️  You have an outdated version installed"
    echo ""
    echo "Installing updated ZSH script..."
    echo ""

    # Run the installation
    cd "$(dirname "$0")"
    ./install-zsh-only.sh

    echo ""
    echo "✅ Updated! Now run these commands:"
    echo ""
    echo "  exec zsh    # Start fresh shell to load new script"
    echo ""
    echo "Then test with:"
    echo "  ai_shell_task \"find all Swift files modified in the last week\""
    exit 0
fi

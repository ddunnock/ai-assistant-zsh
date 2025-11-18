#!/usr/bin/env bash
# Install Apple Swift compiler on Ubuntu
set -e

echo "🔧 Installing Swift Compiler for Linux"
echo ""

# Check if already installed
if command -v swift >/dev/null 2>&1; then
    VERSION=$(swift --version 2>&1 | head -1)
    if [[ "$VERSION" =~ "Swift version" ]]; then
        echo "✓ Swift compiler is already installed:"
        echo "  $VERSION"
        exit 0
    fi
fi

# Install using swiftly (official Swift version manager)
echo "Installing swiftly (Swift version manager)..."
curl -L https://swift-server.github.io/swiftly/swiftly-install.sh | bash

# Source the environment
export PATH="$HOME/.local/bin:$PATH"

# Install latest Swift toolchain
echo ""
echo "Installing Swift toolchain..."
swiftly install latest

echo ""
echo "✓ Swift installation complete!"
echo ""
echo "To use Swift in this shell:"
echo "  source ~/.local/share/swiftly/env.sh"
echo ""
echo "This has been added to your shell profile (~/.bashrc)"
echo ""
echo "Now you can run: ./install-production.sh --production"

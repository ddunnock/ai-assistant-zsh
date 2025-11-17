#!/usr/bin/env bash
# Test script for AI Shell Daemon debugging
set -euo pipefail

echo "==================================="
echo "AI Shell Daemon Debug Test"
echo "==================================="
echo ""

# Clean and rebuild
echo "1. Cleaning build artifacts..."
rm -rf .build
echo "   ✓ Clean complete"
echo ""

# Build
echo "2. Building daemon (release mode)..."
swift build -c release 2>&1 | tee build.log
echo "   ✓ Build complete"
echo ""

# Find binary
echo "3. Locating binary..."
BINARY_PATH=$(find .build -type f -perm +111 -name "*daemon*" 2>/dev/null | head -n1)

if [[ -z "$BINARY_PATH" ]]; then
    echo "   ✗ ERROR: Binary not found!"
    exit 1
fi

echo "   ✓ Found binary at: $BINARY_PATH"
echo ""

# Check binary
echo "4. Binary information:"
file "$BINARY_PATH"
ls -lh "$BINARY_PATH"
echo ""

# Test --help (should work)
echo "5. Testing --help flag:"
"$BINARY_PATH" --help || true
echo ""

# Test --version (should work)
echo "6. Testing --version flag:"
"$BINARY_PATH" --version || true
echo ""

# Create config if needed
CONFIG_DIR="${HOME}/.config/ai-shell"
CONFIG_FILE="${CONFIG_DIR}/config.json"

mkdir -p "$CONFIG_DIR"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "7. Creating test configuration..."
    cat > "$CONFIG_FILE" <<EOF
{
  "socketPath": "/tmp/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "debug",
  "enableMemory": true,
  "enableRAG": true,
  "enableCache": true,
  "enableStreaming": false
}
EOF
    echo "   ✓ Config created at: $CONFIG_FILE"
else
    echo "7. Using existing config: $CONFIG_FILE"
fi
echo ""

# Test with config
echo "8. Testing with --config flag:"
echo "   Command: $BINARY_PATH --config $CONFIG_FILE"
echo "   Output:"
echo "   ----------------------------------------"
"$BINARY_PATH" --config "$CONFIG_FILE" 2>&1 || {
    echo "   ----------------------------------------"
    echo "   ✗ Command failed or was interrupted"
}
echo ""

echo "==================================="
echo "Test Complete"
echo "==================================="
echo ""
echo "If you see DEBUG messages in step 8, please share:"
echo "  - All DEBUG output"
echo "  - Whether the daemon started or showed help"
echo "  - Any errors or unexpected behavior"

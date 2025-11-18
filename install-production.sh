#!/usr/bin/env bash
# AI Shell Assistant - Production Installer
# One-command installation for production or development use
set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Installation mode (default: production)
PRODUCTION_MODE=true
AUTO_START=false
QUIET_MODE=false

# Paths
INSTALL_DIR="/usr/local/bin"
CONFIG_DIR="${HOME}/.config/ai-shell"
ZSH_DIR="${HOME}/.zsh/ai-shell"
BUILD_TYPE="release"

# Socket path - secure location based on platform
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS: use user-specific runtime directory
    SOCKET_PATH="${TMPDIR:-/tmp}/ai-shell-${UID}.sock"
elif [[ -d "/run/user/${UID}" ]]; then
    # Linux with user runtime directory
    SOCKET_PATH="/run/user/${UID}/ai-shell.sock"
else
    # Fallback
    SOCKET_PATH="/tmp/ai-shell-${UID}.sock"
fi

# ============================================================================
# Helper Functions
# ============================================================================

info() { echo -e "${BLUE}ℹ${NC} $1"; }
success() { echo -e "${GREEN}✓${NC} $1"; }
warning() { echo -e "${YELLOW}⚠${NC} $1"; }
error() { echo -e "${RED}✗${NC} $1" >&2; }
section() {
    echo ""
    echo -e "${CYAN}▶ $1${NC}"
    echo "$(printf '=%.0s' {1..60})"
}

usage() {
    cat <<EOF
AI Shell Assistant - Production Installer

Usage: $0 [OPTIONS]

OPTIONS:
    --production         Install for production use (default)
    --dev                Install for development (debug logging enabled)
    --auto-start         Set up auto-start service (launchd/systemd)
    --quiet              Quiet mode (suppress banner on daemon startup)
    --help               Show this help message

EXAMPLES:
    $0                   # Install with production defaults
    $0 --dev             # Install for development
    $0 --production --auto-start --quiet  # Silent production setup

EOF
    exit 0
}

# ============================================================================
# Argument Parsing
# ============================================================================

while [[ $# -gt 0 ]]; do
    case $1 in
        --production)
            PRODUCTION_MODE=true
            shift
            ;;
        --dev)
            PRODUCTION_MODE=false
            BUILD_TYPE="debug"
            shift
            ;;
        --auto-start)
            AUTO_START=true
            shift
            ;;
        --quiet)
            QUIET_MODE=true
            shift
            ;;
        --help|-h)
            usage
            ;;
        *)
            error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# ============================================================================
# Dependency Checks
# ============================================================================

check_dependencies() {
    section "Checking Dependencies"

    local missing=()

    command -v swift >/dev/null 2>&1 || missing+=("swift")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
        echo ""
        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "Install with: brew install ${missing[*]}"
        else
            echo "Install with: sudo apt-get install ${missing[*]}"
        fi
        exit 1
    fi

    success "All required dependencies found"

    # Check Ollama
    if ! command -v ollama >/dev/null 2>&1; then
        warning "Ollama not found - required for AI functionality"
        echo "  Download from: https://ollama.com/download"
        echo ""
    else
        success "Ollama found"
    fi
}

# ============================================================================
# Build Daemon
# ============================================================================

build_daemon() {
    section "Building AI Shell Daemon"

    info "Build type: $BUILD_TYPE"

    if [[ "$BUILD_TYPE" == "release" ]]; then
        swift build -c release
    else
        swift build
    fi

    success "Build complete"
}

# ============================================================================
# Install Components
# ============================================================================

install_daemon() {
    section "Installing Daemon"

    local binary_path
    if [[ "$OSTYPE" == "darwin"* ]]; then
        binary_path=".build/apple/Products/Release/ai-shell-daemon"
        if [[ ! -f "$binary_path" ]]; then
            binary_path=".build/arm64-apple-macosx/release/ai-shell-daemon"
        fi
    else
        binary_path=".build/${BUILD_TYPE}/AIShellDaemon"
    fi

    if [[ ! -f "$binary_path" ]]; then
        error "Binary not found at: $binary_path"
        exit 1
    fi

    # Check if we need sudo for /usr/local/bin
    if [[ -w "$INSTALL_DIR" ]]; then
        cp "$binary_path" "$INSTALL_DIR/ai-shell-daemon"
        chmod +x "$INSTALL_DIR/ai-shell-daemon"
    else
        info "Installing to $INSTALL_DIR requires sudo..."
        sudo cp "$binary_path" "$INSTALL_DIR/ai-shell-daemon"
        sudo chmod +x "$INSTALL_DIR/ai-shell-daemon"
    fi

    success "Daemon installed to $INSTALL_DIR/ai-shell-daemon"
}

install_zsh() {
    section "Installing ZSH Integration"

    mkdir -p "$ZSH_DIR"

    cp "zsh/ai-assistant.zsh" "$ZSH_DIR/ai-assistant.zsh"
    cp "zsh/ai-shell-client.py" "$ZSH_DIR/ai-shell-client.py"
    chmod +x "$ZSH_DIR/ai-assistant.zsh"
    chmod +x "$ZSH_DIR/ai-shell-client.py"

    success "ZSH files installed to $ZSH_DIR"

    # Add to .zshrc if not already present
    local zshrc="${HOME}/.zshrc"
    local source_line="source ${ZSH_DIR}/ai-assistant.zsh"

    if [[ -f "$zshrc" ]] && ! grep -q "$source_line" "$zshrc"; then
        echo "" >> "$zshrc"
        echo "# AI Shell Assistant" >> "$zshrc"
        echo "$source_line" >> "$zshrc"
        success "Added to ~/.zshrc"
    else
        info "Already present in ~/.zshrc"
    fi
}

install_config() {
    section "Creating Configuration"

    mkdir -p "$CONFIG_DIR"

    local config_file="$CONFIG_DIR/config.json"
    local log_level="info"

    if [[ "$PRODUCTION_MODE" == false ]]; then
        log_level="debug"
    fi

    if [[ ! -f "$config_file" ]]; then
        cat > "$config_file" <<EOF
{
  "socketPath": "$SOCKET_PATH",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "$log_level",
  "enableMemory": true,
  "enableRAG": true,
  "enableCache": true,
  "enableStreaming": false
}
EOF
        success "Configuration created: $config_file"
    else
        info "Configuration already exists: $config_file"
    fi

    chmod 644 "$config_file"
}

# ============================================================================
# Auto-Start Service
# ============================================================================

install_launchd_service() {
    section "Setting Up Auto-Start (macOS launchd)"

    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist_file="${plist_dir}/com.aishell.daemon.plist"

    mkdir -p "$plist_dir"

    local quiet_flag=""
    if [[ "$QUIET_MODE" == true ]]; then
        quiet_flag="<string>--quiet</string>"
    fi

    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aishell.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>$INSTALL_DIR/ai-shell-daemon</string>
        <string>--config</string>
        <string>$CONFIG_DIR/config.json</string>
        $quiet_flag
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$CONFIG_DIR/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>$CONFIG_DIR/daemon.error.log</string>
</dict>
</plist>
EOF

    launchctl unload "$plist_file" 2>/dev/null || true
    launchctl load "$plist_file"

    success "Auto-start service installed and started"
}

install_systemd_service() {
    section "Setting Up Auto-Start (Linux systemd)"

    local service_dir="${HOME}/.config/systemd/user"
    local service_file="${service_dir}/ai-shell-daemon.service"

    mkdir -p "$service_dir"

    local quiet_flag=""
    if [[ "$QUIET_MODE" == true ]]; then
        quiet_flag="--quiet"
    fi

    cat > "$service_file" <<EOF
[Unit]
Description=AI Shell Assistant Daemon
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/ai-shell-daemon --config $CONFIG_DIR/config.json $quiet_flag
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    systemctl --user enable ai-shell-daemon.service
    systemctl --user start ai-shell-daemon.service

    success "Auto-start service installed and started"
}

# ============================================================================
# Verification
# ============================================================================

verify_installation() {
    section "Verifying Installation"

    # Check binary
    if command -v ai-shell-daemon >/dev/null 2>&1; then
        success "Daemon binary is in PATH"
    else
        warning "Daemon binary not in PATH (expected at $INSTALL_DIR)"
    fi

    # Check socket (if daemon is running)
    sleep 2  # Give daemon time to start
    if [[ -S "$SOCKET_PATH" ]]; then
        success "Daemon socket exists: $SOCKET_PATH"
    else
        warning "Daemon socket not found (daemon may not be running)"
    fi

    # Check configuration
    if [[ -f "$CONFIG_DIR/config.json" ]]; then
        success "Configuration file exists"
    fi
}

# ============================================================================
# Next Steps
# ============================================================================

show_next_steps() {
    section "Installation Complete!"

    echo ""
    echo -e "${GREEN}🎉 AI Shell Assistant is ready to use!${NC}"
    echo ""
    echo "NEXT STEPS:"
    echo ""
    echo "1. Start a new shell to load the ZSH integration:"
    echo -e "   ${CYAN}exec zsh${NC}"
    echo ""
    echo "2. Try the simplified command syntax:"
    echo -e "   ${CYAN}* find all Swift files in this directory${NC}"
    echo -e "   ${CYAN}* show me disk usage sorted by size${NC}"
    echo -e "   ${CYAN}* list all running processes${NC}"
    echo ""
    echo "3. Check daemon health:"
    echo -e "   ${CYAN}ai_shell_health${NC}  (or: ${CYAN}aih${NC})"
    echo ""
    echo "4. Other useful commands:"
    echo -e "   ${CYAN}ai_shell_explain <command>${NC}  - Explain a command"
    echo -e "   ${CYAN}ai_shell_suggest${NC}            - Get suggestions"
    echo -e "   ${CYAN}ai_shell_remember <fact>${NC}    - Store information"
    echo -e "   ${CYAN}ai_shell_recall <query>${NC}     - Retrieve information"
    echo ""

    if [[ "$AUTO_START" == true ]]; then
        echo "✓ Auto-start is enabled - daemon will start on login"
    else
        echo "To enable auto-start:"
        echo -e "   ${CYAN}$0 --production --auto-start${NC}"
    fi

    echo ""
    echo "CONFIGURATION:"
    echo "  Config file: $CONFIG_DIR/config.json"
    echo "  Socket path: $SOCKET_PATH"
    echo "  Log level:   $(if [[ "$PRODUCTION_MODE" == true ]]; then echo "info"; else echo "debug"; fi)"
    echo ""

    if [[ "$PRODUCTION_MODE" == false ]]; then
        warning "Development mode is active (debug logging enabled)"
        echo "  For production deployment, reinstall with: $0 --production"
        echo ""
    fi

    echo "For more information:"
    echo "  Documentation: https://github.com/yourusername/ai-assistant-zsh"
    echo "  Report issues: https://github.com/yourusername/ai-assistant-zsh/issues"
    echo ""
}

# ============================================================================
# Main Installation Flow
# ============================================================================

main() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}║          AI Shell Assistant - Production Installer         ║${NC}"
    echo -e "${CYAN}║                                                            ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$PRODUCTION_MODE" == true ]]; then
        info "Mode: Production"
    else
        info "Mode: Development"
    fi

    # Don't run as root
    if [[ $EUID -eq 0 ]]; then
        error "Do not run as root"
        echo "Run as regular user - script will ask for sudo when needed"
        exit 1
    fi

    # Run installation steps
    check_dependencies
    build_daemon
    install_daemon
    install_zsh
    install_config

    # Optional auto-start
    if [[ "$AUTO_START" == true ]]; then
        if [[ "$OSTYPE" == "darwin"* ]]; then
            install_launchd_service
        elif command -v systemctl >/dev/null 2>&1; then
            install_systemd_service
        else
            warning "Auto-start not supported on this platform"
        fi
    else
        info "Skipping auto-start setup (use --auto-start to enable)"
    fi

    # Verify and show next steps
    verify_installation
    show_next_steps
}

# Run main function
main

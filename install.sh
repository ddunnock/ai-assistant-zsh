#!/usr/bin/env bash
# Installation script for AI Shell Assistant
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
CONFIG_DIR="${HOME}/.config/ai-shell"
ZSH_PLUGIN_DIR="${HOME}/.oh-my-zsh/custom/plugins/ai-shell"
SOCKET_PATH="${SOCKET_PATH:-/tmp/ai-shell.sock}"
BUILD_TYPE="${BUILD_TYPE:-release}"

# State
NEEDS_SUDO=0
INSTALLED_COMPONENTS=()

# Functions
info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

success() {
    echo -e "${GREEN}✓${NC} $1"
}

warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1" >&2
}

section() {
    echo ""
    echo -e "${CYAN}▶ $1${NC}"
    echo "$(printf '=%.0s' {1..60})"
}

# Check if running as root (we don't want that)
check_not_root() {
    if [[ $EUID -eq 0 ]]; then
        error "Do not run this script as root"
        echo "The script will ask for sudo password when needed" >&2
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    section "Checking Dependencies"

    local missing=()
    local optional_missing=()

    # Required
    command -v swift >/dev/null 2>&1 || missing+=("swift")
    command -v jq >/dev/null 2>&1 || missing+=("jq")
    command -v nc >/dev/null 2>&1 || missing+=("netcat")

    # Optional but recommended
    command -v ollama >/dev/null 2>&1 || optional_missing+=("ollama")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies:"
        printf '  - %s\n' "${missing[@]}"
        echo ""
        echo "Install with:" >&2

        if [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install ${missing[*]}" >&2
        elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
            echo "  sudo apt-get install ${missing[*]}" >&2
        fi

        exit 1
    fi

    success "All required dependencies found"

    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        warning "Optional dependencies missing:"
        printf '  - %s\n' "${optional_missing[@]}"

        if [[ " ${optional_missing[@]} " =~ " ollama " ]]; then
            echo ""
            echo "Ollama is required for AI functionality:"
            echo "  https://ollama.com/download"
            echo ""
        fi
    fi
}

# Check write permissions
check_permissions() {
    if [[ ! -w "$INSTALL_DIR" ]]; then
        info "Installation directory requires sudo: $INSTALL_DIR"
        NEEDS_SUDO=1
    fi
}

# Build the daemon
build_daemon() {
    section "Building AI Shell Daemon"

    if [[ ! -f "build.sh" ]]; then
        error "build.sh not found. Are you in the project directory?"
        exit 1
    fi

    ./build.sh --${BUILD_TYPE}

    local binary_path=".build/${BUILD_TYPE}/ai-shell-daemon"
    if [[ ! -f "$binary_path" ]]; then
        error "Build failed: binary not found at $binary_path"
        exit 1
    fi

    success "Daemon built successfully"
}

# Install the daemon binary
install_daemon() {
    section "Installing Daemon Binary"

    local binary_path=".build/${BUILD_TYPE}/ai-shell-daemon"
    local target_path="${INSTALL_DIR}/ai-shell-daemon"

    info "Installing to: $target_path"

    if [[ $NEEDS_SUDO -eq 1 ]]; then
        sudo cp "$binary_path" "$target_path"
        sudo chmod +x "$target_path"
    else
        cp "$binary_path" "$target_path"
        chmod +x "$target_path"
    fi

    success "Daemon installed to $target_path"
    INSTALLED_COMPONENTS+=("daemon")
}

# Install ZSH plugin
install_zsh_plugin() {
    section "Installing ZSH Plugin"

    # Check if ZSH is the current shell
    if [[ ! "$SHELL" =~ "zsh" ]]; then
        warning "Current shell is not ZSH ($SHELL)"
        echo "You can still use the plugin by sourcing it manually"
        echo ""
    fi

    # Determine installation method
    local install_method="direct"
    local target_dir=""

    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        install_method="oh-my-zsh"
        target_dir="$ZSH_PLUGIN_DIR"
    else
        install_method="direct"
        target_dir="${HOME}/.zsh/ai-shell"
    fi

    info "Installation method: $install_method"

    # Create target directory
    mkdir -p "$target_dir"

    # Copy plugin file
    cp "zsh/ai-assistant.zsh" "$target_dir/ai-assistant.zsh"
    chmod +x "$target_dir/ai-assistant.zsh"

    success "Plugin installed to $target_dir"

    # Add to .zshrc if not already present
    local zshrc="${HOME}/.zshrc"
    local source_line=""

    if [[ "$install_method" == "oh-my-zsh" ]]; then
        # For oh-my-zsh, we need to add it to plugins array
        info "For oh-my-zsh, add 'ai-shell' to your plugins in ~/.zshrc"
        echo ""
        echo "Example:"
        echo "  plugins=(git ai-shell)"
        echo ""
    else
        source_line="source ${target_dir}/ai-assistant.zsh"

        if [[ -f "$zshrc" ]] && ! grep -q "ai-assistant.zsh" "$zshrc"; then
            echo "" >> "$zshrc"
            echo "# AI Shell Assistant" >> "$zshrc"
            echo "$source_line" >> "$zshrc"
            success "Added to ~/.zshrc"
        elif [[ -f "$zshrc" ]]; then
            info "Already present in ~/.zshrc"
        else
            warning "~/.zshrc not found"
            echo "Add this to your ZSH configuration:"
            echo "  $source_line"
            echo ""
        fi
    fi

    INSTALLED_COMPONENTS+=("zsh-plugin")
}

# Create configuration directory and files
install_config() {
    section "Setting Up Configuration"

    mkdir -p "$CONFIG_DIR"
    success "Created config directory: $CONFIG_DIR"

    # Copy example config if it doesn't exist
    local config_file="${CONFIG_DIR}/config.json"

    if [[ ! -f "$config_file" ]]; then
        if [[ -f "config.example.json" ]]; then
            cp "config.example.json" "$config_file"
            success "Created config file: $config_file"
        else
            # Create minimal config
            cat > "$config_file" <<EOF
{
  "socketPath": "$SOCKET_PATH",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "info"
}
EOF
            success "Created default config: $config_file"
        fi
    else
        info "Config file already exists: $config_file"
    fi

    # Set permissions
    chmod 644 "$config_file"

    INSTALLED_COMPONENTS+=("config")
}

# Install launchd service (macOS only)
install_launchd_service() {
    section "Setting Up Auto-Start (macOS)"

    if [[ "$OSTYPE" != "darwin"* ]]; then
        info "Skipping (not macOS)"
        return 0
    fi

    local plist_dir="${HOME}/Library/LaunchAgents"
    local plist_file="${plist_dir}/com.aiassistant.shell.daemon.plist"

    mkdir -p "$plist_dir"

    cat > "$plist_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.aiassistant.shell.daemon</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/ai-shell-daemon</string>
        <string>--config</string>
        <string>${CONFIG_DIR}/config.json</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>${CONFIG_DIR}/daemon.log</string>
    <key>StandardErrorPath</key>
    <string>${CONFIG_DIR}/daemon.error.log</string>
</dict>
</plist>
EOF

    success "Created launchd service: $plist_file"

    # Load the service
    if launchctl list | grep -q "com.aiassistant.shell.daemon"; then
        info "Unloading existing service..."
        launchctl unload "$plist_file" 2>/dev/null || true
    fi

    launchctl load "$plist_file"
    success "Loaded launchd service"

    INSTALLED_COMPONENTS+=("launchd")
}

# Verify Ollama is running
check_ollama() {
    section "Checking Ollama"

    if ! command -v ollama >/dev/null 2>&1; then
        warning "Ollama is not installed"
        echo ""
        echo "Install Ollama from: https://ollama.com/download"
        echo ""
        return 1
    fi

    success "Ollama is installed"

    # Check if Ollama is running
    if curl -s http://localhost:11434/api/tags >/dev/null 2>&1; then
        success "Ollama service is running"

        # List available models
        local models=$(curl -s http://localhost:11434/api/tags | jq -r '.models[].name' 2>/dev/null || echo "")

        if [[ -n "$models" ]]; then
            echo ""
            echo "Available models:"
            echo "$models" | while read -r model; do
                echo "  - $model"
            done
            echo ""

            # Check if default model exists
            if echo "$models" | grep -q "llama3.1:8b"; then
                success "Default model (llama3.1:8b) is available"
            else
                warning "Default model (llama3.1:8b) not found"
                echo ""
                echo "Pull it with:"
                echo "  ollama pull llama3.1:8b"
                echo ""
            fi
        fi
    else
        warning "Ollama service is not running"
        echo ""
        echo "Start Ollama with:"
        echo "  ollama serve"
        echo ""
    fi
}

# Test installation
test_installation() {
    section "Testing Installation"

    # Test daemon binary
    if command -v ai-shell-daemon >/dev/null 2>&1; then
        local version=$(ai-shell-daemon --version 2>&1 | head -n1 || echo "unknown")
        success "Daemon is in PATH: $version"
    else
        error "Daemon not found in PATH"
        echo "You may need to add $INSTALL_DIR to your PATH" >&2
    fi

    # Test if daemon is running
    if [[ -S "$SOCKET_PATH" ]]; then
        success "Daemon is running (socket exists)"

        # Try a health check
        if [[ -f "${HOME}/.zsh/ai-shell/ai-assistant.zsh" ]] || [[ -f "$ZSH_PLUGIN_DIR/ai-assistant.zsh" ]]; then
            info "To test, open a new terminal and run: ai_shell_health"
        fi
    else
        warning "Daemon is not running yet"
        echo ""
        echo "Start manually with:"
        echo "  ai-shell-daemon --config ${CONFIG_DIR}/config.json"
        echo ""
        echo "Or reload your shell to auto-start (if launchd is configured)"
    fi
}

# Show post-installation instructions
show_post_install() {
    section "Installation Complete!"

    echo ""
    echo "Installed components:"
    printf '  ✓ %s\n' "${INSTALLED_COMPONENTS[@]}"
    echo ""

    echo "Next steps:"
    echo ""
    echo "1. Make sure Ollama is running:"
    echo "   ollama serve"
    echo ""
    echo "2. Pull a model if needed:"
    echo "   ollama pull llama3.1:8b"
    echo ""
    echo "3. Start the daemon (if not auto-started):"
    echo "   ai-shell-daemon --config ${CONFIG_DIR}/config.json"
    echo ""
    echo "4. Open a new terminal or reload ZSH:"
    echo "   source ~/.zshrc"
    echo ""
    echo "5. Try it out:"
    echo "   ai_shell_health              # Check daemon status"
    echo "   ai_shell_task <description>  # Convert task to commands"
    echo "   Ctrl+Space                   # Get AI suggestion (in terminal)"
    echo ""

    success "Enjoy your AI-powered shell!"
}

# Uninstall function
uninstall() {
    section "Uninstalling AI Shell Assistant"

    # Stop and unload launchd service
    if [[ "$OSTYPE" == "darwin"* ]]; then
        local plist_file="${HOME}/Library/LaunchAgents/com.aiassistant.shell.daemon.plist"
        if [[ -f "$plist_file" ]]; then
            launchctl unload "$plist_file" 2>/dev/null || true
            rm "$plist_file"
            success "Removed launchd service"
        fi
    fi

    # Remove daemon binary
    if [[ -f "${INSTALL_DIR}/ai-shell-daemon" ]]; then
        if [[ -w "$INSTALL_DIR" ]]; then
            rm "${INSTALL_DIR}/ai-shell-daemon"
        else
            sudo rm "${INSTALL_DIR}/ai-shell-daemon"
        fi
        success "Removed daemon binary"
    fi

    # Remove ZSH plugin
    if [[ -d "${HOME}/.zsh/ai-shell" ]]; then
        rm -rf "${HOME}/.zsh/ai-shell"
        success "Removed ZSH plugin"
    fi

    if [[ -d "$ZSH_PLUGIN_DIR" ]]; then
        rm -rf "$ZSH_PLUGIN_DIR"
        success "Removed oh-my-zsh plugin"
    fi

    # Ask about config
    echo ""
    echo -n "Remove configuration directory (${CONFIG_DIR})? [y/N] "
    read -r confirm

    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        rm -rf "$CONFIG_DIR"
        success "Removed configuration"
    else
        info "Kept configuration in $CONFIG_DIR"
    fi

    success "Uninstall complete"
}

# Main installation function
main() {
    local skip_build=0
    local skip_launchd=0
    local do_uninstall=0
    local show_help=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --skip-build)
                skip_build=1
                shift
                ;;
            --skip-launchd)
                skip_launchd=1
                shift
                ;;
            --uninstall)
                do_uninstall=1
                shift
                ;;
            --debug)
                BUILD_TYPE="debug"
                shift
                ;;
            --help|-h)
                show_help=1
                shift
                ;;
            *)
                error "Unknown option: $1"
                show_help=1
                shift
                ;;
        esac
    done

    if [[ $show_help -eq 1 ]]; then
        cat <<EOF
Usage: $0 [OPTIONS]

Install the AI Shell Assistant

OPTIONS:
    --skip-build     Skip building the daemon (use existing binary)
    --skip-launchd   Skip setting up launchd auto-start (macOS)
    --debug          Install debug build instead of release
    --uninstall      Uninstall AI Shell Assistant
    -h, --help       Show this help message

ENVIRONMENT VARIABLES:
    INSTALL_DIR      Installation directory (default: /usr/local/bin)
    CONFIG_DIR       Configuration directory (default: ~/.config/ai-shell)
    BUILD_TYPE       Build type (debug|release, default: release)

EXAMPLES:
    $0                    # Full installation
    $0 --skip-build       # Install using existing binary
    $0 --uninstall        # Remove installation
EOF
        exit 0
    fi

    if [[ $do_uninstall -eq 1 ]]; then
        uninstall
        exit 0
    fi

    echo "AI Shell Assistant - Installation Script"
    echo "========================================="
    echo ""

    check_not_root
    check_dependencies
    check_permissions

    if [[ $skip_build -eq 0 ]]; then
        build_daemon
    fi

    install_daemon
    install_zsh_plugin
    install_config

    if [[ $skip_launchd -eq 0 ]] && [[ "$OSTYPE" == "darwin"* ]]; then
        install_launchd_service
    fi

    check_ollama
    test_installation
    show_post_install
}

# Run main function
main "$@"

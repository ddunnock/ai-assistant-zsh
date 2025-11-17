# AI Shell Assistant

> Warp Terminal-like AI assistance using local LLM models for ZSH

AI Shell Assistant brings powerful AI capabilities to your command line using local LLM models via [Ollama](https://ollama.com). Get intelligent command suggestions, explanations, and convert natural language into shell commands - all running locally on your machine.

## Features

### 🤖 AI-Powered Command Assistance
- **Smart Suggestions**: Get intelligent command completions and improvements
- **Command Explanations**: Understand what complex commands do before running them
- **Natural Language to Shell**: Convert plain English into executable commands
- **Context-Aware**: Uses your command history, git branch, and working directory

### 🔒 Privacy-Focused
- **100% Local**: All AI processing happens on your machine via Ollama
- **No Cloud**: No data sent to external services
- **Offline Capable**: Works without internet connection

### ⚡ Performance
- **Fast Responses**: Optimized for quick suggestions using local models
- **Lightweight**: Minimal overhead on your shell
- **Async Processing**: Non-blocking AI suggestions

### 🛠 Developer-Friendly
- **Multiple Models**: Support for llama3.1, codellama, mistral, and more
- **Configurable**: Customize prompts, models, and behavior
- **ZSH Integration**: Seamless integration with your existing ZSH setup

## Demo

```bash
# Get AI suggestions with Ctrl+Space
$ git co<Ctrl+Space>
# → git checkout main

# Explain commands with Ctrl+X e
$ tar -xzvf archive.tar.gz
# Shows: "This command extracts a gzipped tar archive..."

# Convert natural language to commands
$ ait find all python files modified in last week
# Suggested commands:
# find . -name "*.py" -type f -mtime -7

# Check daemon status
$ aih
# ✓ AI Shell Assistant daemon is healthy
```

## Architecture

```
┌─────────────────────────────────┐
│       ZSH Terminal              │
│   (ai-assistant.zsh plugin)     │
└───────────┬─────────────────────┘
            │ Unix Socket
            │ /tmp/ai-shell.sock
            ▼
┌─────────────────────────────────┐
│    AI Shell Daemon (Swift)      │
│  - Request routing              │
│  - Prompt engineering           │
│  - Response formatting          │
└───────────┬─────────────────────┘
            │ HTTP
            ▼
┌─────────────────────────────────┐
│      Ollama (Local LLM)         │
│  - llama3.1:8b (default)        │
│  - codellama, mistral, etc.     │
└─────────────────────────────────┘
```

## Installation

### Prerequisites

1. **macOS 13+ or Linux** (tested on Ubuntu 20.04+)
2. **Swift 5.9+** - [Download Swift](https://swift.org/download/)
3. **Ollama** - [Install Ollama](https://ollama.com/download)
4. **ZSH** - Should be your default shell
5. **Dependencies**: `jq`, `netcat`

#### Install Dependencies (macOS)
```bash
brew install swift jq netcat
brew install ollama
```

#### Install Dependencies (Linux)
```bash
# Swift (follow official instructions)
# https://swift.org/install/linux/

sudo apt-get update
sudo apt-get install jq netcat-openbsd
curl -fsSL https://ollama.com/install.sh | sh
```

### Quick Install

```bash
# Clone the repository
git clone https://github.com/yourusername/ai-assistant-zsh.git
cd ai-assistant-zsh

# Run the installation script
./install.sh
```

The installer will:
1. Build the Swift daemon
2. Install the binary to `/usr/local/bin`
3. Install the ZSH plugin
4. Create configuration directory
5. Set up auto-start (macOS via launchd)

### Manual Installation

```bash
# Build the daemon
./build.sh

# Copy binary
sudo cp .build/release/ai-shell-daemon /usr/local/bin/

# Install ZSH plugin
mkdir -p ~/.zsh/ai-shell
cp zsh/ai-assistant.zsh ~/.zsh/ai-shell/

# Add to ~/.zshrc
echo 'source ~/.zsh/ai-shell/ai-assistant.zsh' >> ~/.zshrc

# Create config
mkdir -p ~/.config/ai-shell
cp config.example.json ~/.config/ai-shell/config.json
```

### Post-Installation

```bash
# Pull the default model
ollama pull llama3.1:8b

# Start Ollama (if not running)
ollama serve &

# Start the daemon
ai-shell-daemon --config ~/.config/ai-shell/config.json &

# Reload ZSH
source ~/.zshrc

# Test it
ai_shell_health
```

## Usage

### Commands

#### `ai_shell_task` / `ait`
Convert natural language descriptions into shell commands.

```bash
ait find all javascript files larger than 1MB
ait create a backup of my home directory
ait show me the top 10 memory consuming processes
```

#### `ai_shell_explain` / `aix`
Get detailed explanations of shell commands.

```bash
aix "tar -xzvf archive.tar.gz"
aix "awk '{print $1}' file.txt | sort | uniq -c'"
```

#### `ai_shell_health` / `aih`
Check if the daemon is running and healthy.

```bash
aih
# ✓ AI Shell Assistant daemon is healthy
#   Socket: /tmp/ai-shell.sock
```

### Keybindings

| Key | Action |
|-----|--------|
| `Ctrl+Space` | Get AI suggestion for current command |
| `Ctrl+X e` | Explain current command |

### Configuration

Edit `~/.config/ai-shell/config.json`:

```json
{
  "socketPath": "/tmp/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "info"
}
```

See [CONFIGURATION.md](docs/CONFIGURATION.md) for detailed configuration options.

### Environment Variables

Set these in your `~/.zshrc`:

```bash
export AI_SHELL_SOCKET="/tmp/ai-shell.sock"
export AI_SHELL_AUTO_START="1"       # Auto-start daemon
export AI_SHELL_DEBUG="0"            # Enable debug output
```

## Model Selection

### Recommended Models

| Model | Speed | Quality | Memory | Use Case |
|-------|-------|---------|--------|----------|
| `llama3.1:8b` | ⚡⚡⚡ | ⭐⭐⭐ | 8 GB | Default, balanced |
| `codellama:13b` | ⚡⚡ | ⭐⭐⭐⭐ | 16 GB | Code-focused |
| `mistral:latest` | ⚡⚡⚡ | ⭐⭐⭐ | 6 GB | Fast, lightweight |
| `qwen2.5-coder:7b` | ⚡⚡⚡ | ⭐⭐⭐ | 6 GB | Code generation |

### Pulling Models

```bash
# Pull a specific model
ollama pull llama3.1:8b

# List installed models
ollama list

# Remove a model
ollama rm model-name
```

## Development

### Building from Source

```bash
# Build in debug mode
./build.sh --debug

# Build with tests
./build.sh --clean --test

# Build with verbose output
./build.sh --verbose
```

### Project Structure

```
ai-assistant-zsh/
├── Sources/
│   ├── AIShellDaemon/          # Daemon executable
│   │   ├── main.swift          # Entry point
│   │   ├── Configuration.swift # Config management
│   │   └── DaemonService.swift # Service orchestration
│   └── AIShellCore/            # Core library
│       ├── Clients/            # Ollama HTTP client
│       ├── Models/             # Data models
│       ├── Server/             # Unix socket server
│       └── Utilities/          # Helpers and extensions
├── Tests/                      # Unit and integration tests
├── zsh/                        # ZSH integration
├── docs/                       # Documentation
├── build.sh                    # Build script
├── install.sh                  # Installation script
└── Package.swift               # Swift package manifest
```

### Running Tests

```bash
# Run all tests
swift test

# Run with verbose output
swift test --verbose

# Run specific test
swift test --filter OllamaClientTests
```

### Architecture Details

The system consists of three main components:

1. **ZSH Plugin** (`zsh/ai-assistant.zsh`)
   - Provides shell functions and keybindings
   - Communicates with daemon via Unix socket
   - Handles user interaction and display

2. **Swift Daemon** (`Sources/AIShellDaemon/`)
   - Background service listening on Unix socket
   - Routes requests to appropriate handlers
   - Manages Ollama communication

3. **Ollama Service**
   - Runs LLM models locally
   - Provides HTTP API for text generation
   - Handles model management

See [ARCHITECTURE.md](docs/ARCHITECTURE.md) for detailed architecture documentation.

## Troubleshooting

### Daemon Won't Start

```bash
# Check if Ollama is running
curl http://localhost:11434/api/tags

# Check logs
tail -f ~/.config/ai-shell/daemon.error.log

# Start daemon manually with verbose logging
ai-shell-daemon --config ~/.config/ai-shell/config.json --verbose
```

### ZSH Plugin Not Working

```bash
# Verify daemon is running
ai_shell_health

# Check if socket exists
ls -la /tmp/ai-shell.sock

# Test socket connection
echo '{"id":"test","type":"health","payload":{},"timestamp":"2025-01-01T00:00:00Z"}' | nc -U /tmp/ai-shell.sock
```

### Slow Responses

```bash
# Use a smaller/faster model
ollama pull mistral:latest

# Update config.json
{
  "model": "mistral:latest"
}

# Restart daemon
killall ai-shell-daemon
ai-shell-daemon --config ~/.config/ai-shell/config.json &
```

### Permission Denied

```bash
# Check socket permissions
ls -la /tmp/ai-shell.sock

# Restart daemon
killall ai-shell-daemon
ai-shell-daemon --config ~/.config/ai-shell/config.json &
```

### Model Not Found

```bash
# Pull the model
ollama pull llama3.1:8b

# List available models
ollama list

# Update config to use available model
```

## Uninstallation

```bash
./install.sh --uninstall
```

Or manually:

```bash
# Stop daemon
killall ai-shell-daemon

# Remove launchd service (macOS)
launchctl unload ~/Library/LaunchAgents/com.aiassistant.shell.daemon.plist
rm ~/Library/LaunchAgents/com.aiassistant.shell.daemon.plist

# Remove binary
sudo rm /usr/local/bin/ai-shell-daemon

# Remove ZSH plugin
rm -rf ~/.zsh/ai-shell

# Remove configuration (optional)
rm -rf ~/.config/ai-shell

# Remove from ~/.zshrc
# (manually remove the source line)
```

## Contributing

Contributions are welcome! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Development Setup

```bash
# Clone repository
git clone https://github.com/yourusername/ai-assistant-zsh.git
cd ai-assistant-zsh

# Build and run tests
./build.sh --clean --test

# Install in development mode
./install.sh --debug
```

## Roadmap

- [ ] Streaming responses for better UX
- [ ] Customizable system prompts
- [ ] Response caching for frequent commands
- [ ] Multi-model support with automatic switching
- [ ] Integration with other shells (Bash, Fish)
- [ ] Web dashboard for monitoring
- [ ] Plugin system for extensibility
- [ ] Command safety checks (warn on dangerous operations)
- [ ] Session context persistence
- [ ] Integration with git, docker, kubernetes contexts

## License

MIT License - see [LICENSE](LICENSE) for details

## Credits

- Built with [Swift](https://swift.org)
- Powered by [Ollama](https://ollama.com)
- Inspired by [Warp Terminal](https://warp.dev)

## FAQ

### Is this like GitHub Copilot for the terminal?

Yes! But it runs completely locally using open-source models via Ollama. No cloud, no subscription.

### What models can I use?

Any model supported by Ollama: llama3.1, codellama, mistral, qwen, and many more. See [Ollama Library](https://ollama.com/library).

### Does it work offline?

Yes! Once you've pulled the models, everything runs locally.

### How much RAM do I need?

Depends on the model:
- 7-8B models: 8 GB RAM
- 13B models: 16 GB RAM
- 70B models: 64+ GB RAM

### Can I use it with Bash or Fish?

Currently ZSH only, but the daemon is shell-agnostic. Contributions for other shells welcome!

### Is it safe to execute suggested commands?

The AI generates suggestions, but **you** decide what to run. Always review commands before executing, especially those involving:
- File deletion (`rm -rf`)
- System changes (`sudo`)
- Network operations
- Sensitive data

### How do I customize the prompts?

Currently prompts are in the source code (`Sources/AIShellCore/Server/RequestHandler.swift`). We're working on making them configurable.

### Can I use a remote Ollama instance?

Yes! Change `ollamaURL` in `config.json` to point to your remote Ollama server.

## Support

- **Issues**: [GitHub Issues](https://github.com/yourusername/ai-assistant-zsh/issues)
- **Discussions**: [GitHub Discussions](https://github.com/yourusername/ai-assistant-zsh/discussions)
- **Documentation**: [docs/](docs/)

---

**Made with ❤️ for developers who love the command line**

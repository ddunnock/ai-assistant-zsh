# Configuration Guide

The AI Shell Assistant daemon can be configured via a JSON configuration file or command-line arguments.

## Configuration File Location

The default configuration file location is `~/.config/ai-shell/config.json`.

You can specify a custom location using the `--config` flag:

```bash
ai-shell-daemon --config /path/to/config.json
```

## Configuration Options

### Example Configuration

```json
{
  "socketPath": "/tmp/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "info"
}
```

### Option Details

#### `socketPath`
- **Type:** String
- **Default:** `/tmp/ai-shell.sock`
- **Description:** Unix domain socket path for communication between ZSH and the daemon
- **Example:** `"/tmp/ai-shell.sock"`

#### `ollamaURL`
- **Type:** String
- **Default:** `http://localhost:11434`
- **Description:** Base URL for the Ollama API service
- **Example:** `"http://localhost:11434"`
- **Notes:**
  - Change this if Ollama is running on a different host/port
  - Must include the protocol (`http://` or `https://`)

#### `model`
- **Type:** String
- **Default:** `llama3.1:8b`
- **Description:** The Ollama model to use for AI assistance
- **Example:** `"llama3.1:8b"`, `"codellama:13b"`, `"mistral:latest"`
- **Notes:**
  - Model must be pulled first: `ollama pull <model>`
  - Different models have different capabilities and performance
  - See available models: `ollama list`

#### `logLevel`
- **Type:** String
- **Default:** `info`
- **Description:** Logging verbosity level
- **Options:** `"trace"`, `"debug"`, `"info"`, `"notice"`, `"warning"`, `"error"`, `"critical"`
- **Example:** `"debug"` for development, `"info"` for production

## Command-Line Overrides

Command-line arguments override configuration file settings:

```bash
# Override socket path
ai-shell-daemon --socket /custom/path.sock

# Enable verbose logging (sets logLevel to "debug")
ai-shell-daemon --verbose

# Combine options
ai-shell-daemon --config custom.json --socket /tmp/custom.sock --verbose
```

## Environment Variables

The ZSH plugin also supports environment variables for client-side configuration:

### `AI_SHELL_SOCKET`
- **Default:** `/tmp/ai-shell.sock`
- **Description:** Unix socket path (must match daemon configuration)
- **Example:** `export AI_SHELL_SOCKET="/custom/path.sock"`

### `AI_SHELL_SUGGESTION_COLOR`
- **Default:** `8` (gray)
- **Description:** Color code for inline suggestions
- **Example:** `export AI_SHELL_SUGGESTION_COLOR="10"` (green)

### `AI_SHELL_ENABLE_INLINE`
- **Default:** `1` (enabled)
- **Description:** Enable/disable inline suggestions
- **Example:** `export AI_SHELL_ENABLE_INLINE="0"` to disable

### `AI_SHELL_DEBUG`
- **Default:** `0` (disabled)
- **Description:** Enable debug output in ZSH plugin
- **Example:** `export AI_SHELL_DEBUG="1"`

### `AI_SHELL_AUTO_START`
- **Default:** `0` (disabled)
- **Description:** Automatically start daemon when ZSH loads
- **Example:** `export AI_SHELL_AUTO_START="1"`

## Model Selection Guide

### Recommended Models

| Model | Size | Speed | Quality | Use Case |
|-------|------|-------|---------|----------|
| `llama3.1:8b` | 8B | Fast | Good | General purpose, default |
| `codellama:13b` | 13B | Medium | Better | Code-focused tasks |
| `mistral:latest` | 7B | Fast | Good | Lightweight, fast responses |
| `llama3.1:70b` | 70B | Slow | Best | Maximum quality, slower |
| `qwen2.5-coder:7b` | 7B | Fast | Good | Code generation |

### Pulling Models

```bash
# Pull the default model
ollama pull llama3.1:8b

# Pull a code-specific model
ollama pull codellama:13b

# List available models
ollama list
```

## Performance Tuning

### For Faster Responses
- Use smaller models (7B-8B parameters)
- Example: `mistral:latest`, `llama3.1:8b`

### For Better Quality
- Use larger models (13B-70B parameters)
- Example: `codellama:13b`, `llama3.1:70b`
- Note: Requires more RAM and slower response times

### For Code Tasks
- Use code-specialized models
- Example: `codellama:13b`, `qwen2.5-coder:7b`

## Log Files

When running as a launchd service (macOS), logs are written to:

- **Standard output:** `~/.config/ai-shell/daemon.log`
- **Error output:** `~/.config/ai-shell/daemon.error.log`

When running manually, logs go to:
- macOS: Uses OS.log (view with Console.app)
- Stdout: Structured logs in JSON format (if verbose)

## Example Configurations

### Development Configuration

```json
{
  "socketPath": "/tmp/ai-shell-dev.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "debug"
}
```

### Production Configuration

```json
{
  "socketPath": "/var/run/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "codellama:13b",
  "logLevel": "warning"
}
```

### Remote Ollama Configuration

```json
{
  "socketPath": "/tmp/ai-shell.sock",
  "ollamaURL": "http://192.168.1.100:11434",
  "model": "llama3.1:70b",
  "logLevel": "info"
}
```

## Troubleshooting

### Daemon won't start
1. Check Ollama is running: `curl http://localhost:11434/api/tags`
2. Check socket permissions: `ls -la /tmp/ai-shell.sock`
3. Check logs: `cat ~/.config/ai-shell/daemon.error.log`

### ZSH plugin not working
1. Verify daemon is running: `ai_shell_health`
2. Check socket path matches: `echo $AI_SHELL_SOCKET`
3. Test socket: `nc -U /tmp/ai-shell.sock`

### Slow responses
1. Use a smaller model: Change `model` to `llama3.1:8b` or `mistral:latest`
2. Check Ollama performance: `ollama ps`
3. Ensure Ollama has enough RAM

### Model not found
1. Pull the model: `ollama pull llama3.1:8b`
2. List available models: `ollama list`
3. Update config to use an available model

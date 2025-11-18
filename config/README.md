# Configuration Templates

This directory contains example configuration files for different deployment scenarios.

## Files

### `production.json`
Production-ready configuration with:
- Info-level logging (minimal output)
- Secure socket location
- Optimized caching and memory settings
- Recommended for deployed systems

### `development.json`
Development configuration with:
- Debug logging enabled
- Relaxed security for easier testing
- Shorter cache/memory retention
- Recommended for local development

## Usage

Copy the appropriate template to your config directory:

```bash
# For production
cp config/production.json ~/.config/ai-shell/config.json

# For development
cp config/development.json ~/.config/ai-shell/config.json
```

Or use the installer:

```bash
# Automatically creates production config
./install-production.sh --production

# Automatically creates development config
./install-production.sh --dev
```

## Configuration Options

| Option | Type | Description | Default |
|--------|------|-------------|---------|
| `socketPath` | string | Path to Unix domain socket | `/tmp/ai-shell.sock` |
| `ollamaURL` | string | Ollama API endpoint | `http://localhost:11434` |
| `model` | string | Ollama model to use | `llama3.1:8b` |
| `logLevel` | string | Log verbosity: `debug`, `info`, `warning`, `error` | `info` |
| `enableMemory` | boolean | Enable conversation memory | `true` |
| `enableRAG` | boolean | Enable RAG for documentation | `true` |
| `enableCache` | boolean | Enable response caching | `true` |
| `enableStreaming` | boolean | Enable streaming responses | `false` |
| `maxMemoryAge` | integer | Memory retention in hours | `168` (7 days) |
| `maxCacheAge` | integer | Cache retention in days | `7` |
| `ragMinSimilarity` | float | Minimum similarity for RAG (0.0-1.0) | `0.7` |

## Socket Path Security

### macOS
Recommended: `${TMPDIR}ai-shell-${UID}.sock`

### Linux with systemd
Recommended: `/run/user/${UID}/ai-shell.sock`

### Fallback
Use: `/tmp/ai-shell-${UID}.sock`

The installer automatically selects the most secure option for your platform.

## Log Levels

- **debug**: Verbose output, shows all operations (development only)
- **info**: Normal operational messages (production default)
- **warning**: Important warnings and potential issues
- **error**: Only errors (minimal output)

## Model Selection

Common Ollama models:
- `llama3.1:8b` - Balanced performance and quality (recommended)
- `llama3.1:70b` - Highest quality, requires powerful hardware
- `codellama:34b` - Optimized for code generation
- `mistral:7b` - Fast, lightweight alternative

Check available models: `ollama list`
Pull new models: `ollama pull <model-name>`

## Advanced Configuration

### Custom Storage Paths

You can override default storage locations:

```json
{
  "memoryStoragePath": "/custom/path/memory.json",
  "ragStoragePath": "/custom/path/embeddings.json",
  "cacheStoragePath": "/custom/path/cache.json",
  "promptsStoragePath": "/custom/path/prompts.json"
}
```

Default paths (if not specified):
- Memory: `~/.config/ai-shell/memory.json`
- RAG: `~/.config/ai-shell/embeddings.json`
- Cache: `~/.config/ai-shell/cache.json`
- Prompts: `~/.config/ai-shell/prompts.json`

### Performance Tuning

For high-volume usage:
```json
{
  "enableCache": true,
  "maxCacheAge": 30,
  "ragMinSimilarity": 0.8
}
```

For maximum accuracy (slower):
```json
{
  "enableCache": false,
  "ragMinSimilarity": 0.9
}
```

## Validation

The daemon validates configuration on startup. Common errors:

- **Invalid log level**: Must be `debug`, `info`, `warning`, or `error`
- **Invalid URL**: Must start with `http://` or `https://`
- **Empty values**: `model` and `socketPath` cannot be empty
- **Invalid ranges**: `maxMemoryAge` ≥ 1, `maxCacheAge` ≥ 1, `ragMinSimilarity` 0.0-1.0

## Environment Variables

Override configuration via environment:

```bash
# Override socket path
SOCKET_PATH=/custom/path/socket ./install-production.sh

# Override install directory
INSTALL_DIR=/opt/local/bin ./install-production.sh
```

## Troubleshooting

### Daemon won't start
Check configuration validation:
```bash
ai-shell-daemon --config ~/.config/ai-shell/config.json
```

### Can't connect to Ollama
Verify Ollama is running:
```bash
curl http://localhost:11434/api/tags
```

### Permission denied on socket
Ensure socket path is writable:
```bash
ls -la $(dirname /path/to/socket)
```

## See Also

- [Production Deployment Guide](../README-PRODUCTION.md)
- [Security Guide](../SECURITY.md)
- [Main README](../README.md)

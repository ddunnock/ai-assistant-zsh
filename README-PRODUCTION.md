# AI Shell Assistant - Production Deployment Guide

This guide covers deploying AI Shell Assistant in production environments with best practices for security, performance, and reliability.

## Table of Contents

- [Quick Start](#quick-start)
- [System Requirements](#system-requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Security](#security)
- [Performance Tuning](#performance-tuning)
- [Monitoring](#monitoring)
- [Troubleshooting](#troubleshooting)
- [Maintenance](#maintenance)

## Quick Start

For a standard production deployment:

```bash
# Clone repository
git clone https://github.com/yourusername/ai-assistant-zsh.git
cd ai-assistant-zsh

# Install with production defaults
./install-production.sh --production --auto-start --quiet

# Start new shell
exec zsh

# Test installation
ai_shell_health
```

That's it! The system is ready for use.

## System Requirements

### Minimum Requirements

- **OS**: macOS 11+ or Linux (Ubuntu 20.04+, Debian 11+, etc.)
- **Architecture**: x86_64 or ARM64
- **Memory**: 2 GB RAM (4+ GB recommended for larger models)
- **Disk**: 500 MB for daemon + model size (typically 4-8 GB per model)
- **Swift**: 5.9 or later
- **Ollama**: Latest version

### Recommended Production Specs

- **Memory**: 8+ GB RAM for smooth performance
- **CPU**: 4+ cores for better responsiveness
- **Disk**: SSD for optimal model loading speed
- **Network**: Low-latency connection to Ollama (localhost ideal)

## Installation

### Standard Production Installation

The production installer handles everything automatically:

```bash
./install-production.sh --production --auto-start --quiet
```

This will:
1. ✅ Check dependencies (swift, jq, python3, ollama)
2. ✅ Build daemon in release mode (optimized)
3. ✅ Install daemon to `/usr/local/bin`
4. ✅ Install ZSH integration to `~/.zsh/ai-shell`
5. ✅ Create production config in `~/.config/ai-shell`
6. ✅ Set up auto-start service (launchd/systemd)
7. ✅ Verify installation
8. ✅ Provide next steps

### Custom Installation Paths

Override default paths with environment variables:

```bash
# Install daemon to custom location
INSTALL_DIR=/opt/ai-shell/bin ./install-production.sh --production

# Use custom config directory
CONFIG_DIR=/etc/ai-shell ./install-production.sh --production
```

### Multi-User Installation

For system-wide deployment:

```bash
# Install daemon globally
sudo INSTALL_DIR=/usr/local/bin ./install-production.sh --production

# Each user runs ZSH setup
./install-zsh-only.sh
```

## Configuration

### Production Configuration Template

Located at `config/production.json`:

```json
{
  "socketPath": "/var/run/user/1000/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "info",
  "enableMemory": true,
  "enableRAG": true,
  "enableCache": true,
  "enableStreaming": false,
  "maxMemoryAge": 168,
  "maxCacheAge": 7,
  "ragMinSimilarity": 0.7
}
```

### Key Production Settings

**Logging**
- `logLevel: "info"` - Minimal logging for production
- `logLevel: "warning"` - Only warnings and errors
- `logLevel: "error"` - Only errors (quietest)

**Socket Security**
- Use user-specific paths: `/var/run/user/${UID}/ai-shell.sock`
- Permissions automatically set to 0600 (owner only)
- Never use `/tmp` for production (use installer defaults)

**Performance**
- `enableCache: true` - Significantly improves response times
- `maxCacheAge: 7` - Balance between freshness and performance
- `model: "llama3.1:8b"` - Best balance of speed and quality

**Memory Management**
- `maxMemoryAge: 168` (7 days) - Reasonable retention
- `enableMemory: true` - Improves contextual responses
- Increase for long-term projects, decrease for ephemeral use

### Environment-Specific Configs

**Development**
```bash
cp config/development.json ~/.config/ai-shell/config.json
```

**Staging**
```bash
cp config/production.json ~/.config/ai-shell/config.json
# Edit to point to staging Ollama instance
sed -i 's/localhost/staging-ollama.internal/' ~/.config/ai-shell/config.json
```

**Production**
```bash
# Installer creates this automatically
./install-production.sh --production
```

## Security

See [SECURITY.md](SECURITY.md) for comprehensive security guide.

### Quick Security Checklist

- ✅ Use secure socket paths (not `/tmp`)
- ✅ Run daemon as regular user (never root)
- ✅ Keep Ollama local (localhost:11434)
- ✅ Set appropriate file permissions (config: 644, socket: 600)
- ✅ Enable logging for audit trail
- ✅ Review commands before execution (built-in confirmation)
- ✅ Keep system and dependencies updated

### Network Security

**Firewall Rules** (if Ollama is remote):
```bash
# Allow only from daemon host
sudo ufw allow from 192.168.1.100 to any port 11434
```

**TLS/SSL** (if Ollama is remote):
```json
{
  "ollamaURL": "https://ollama.internal:11434"
}
```

## Performance Tuning

### Model Selection

Choose based on your performance needs:

| Model | Size | Speed | Quality | Use Case |
|-------|------|-------|---------|----------|
| `llama3.1:8b` | 4.7 GB | Fast | Good | **Recommended for production** |
| `llama3.1:70b` | 40 GB | Slow | Excellent | High-end servers only |
| `codellama:34b` | 19 GB | Medium | Very Good | Code-heavy workflows |
| `mistral:7b` | 4.1 GB | Very Fast | Good | Resource-constrained environments |

### Cache Optimization

**High-Volume Usage** (many similar queries):
```json
{
  "enableCache": true,
  "maxCacheAge": 30
}
```

**Dynamic Environments** (frequently changing codebase):
```json
{
  "enableCache": true,
  "maxCacheAge": 1
}
```

**Memory-Constrained** (limited disk space):
```json
{
  "enableCache": false
}
```

### Resource Limits

**macOS (launchd)**

Edit `~/Library/LaunchAgents/com.aishell.daemon.plist`:

```xml
<key>SoftResourceLimits</key>
<dict>
    <key>NumberOfFiles</key>
    <integer>256</integer>
</dict>
```

**Linux (systemd)**

Edit `~/.config/systemd/user/ai-shell-daemon.service`:

```ini
[Service]
MemoryMax=512M
CPUQuota=50%
```

Then reload:
```bash
systemctl --user daemon-reload
systemctl --user restart ai-shell-daemon
```

## Monitoring

### Health Checks

**Manual Health Check**:
```bash
ai_shell_health
# or
aih
```

**Automated Monitoring** (add to cron/systemd timer):
```bash
#!/bin/bash
if ! ai_shell_health &>/dev/null; then
    echo "AI Shell Daemon is down!" | mail -s "Alert" admin@example.com
fi
```

### Logs

**macOS (launchd)**:
```bash
# Daemon output
tail -f ~/.config/ai-shell/daemon.log

# Errors
tail -f ~/.config/ai-shell/daemon.error.log
```

**Linux (systemd)**:
```bash
# All logs
journalctl --user -u ai-shell-daemon -f

# Errors only
journalctl --user -u ai-shell-daemon -p err -f
```

### Performance Metrics

Monitor these indicators:

1. **Response Time**: Should be < 5s for typical queries
2. **Cache Hit Rate**: Check cache file size growth
3. **Memory Usage**: Monitor daemon RSS
4. **Ollama Health**: `curl http://localhost:11434/api/tags`

## Troubleshooting

### Common Issues

#### Daemon Won't Start

**Check configuration**:
```bash
ai-shell-daemon --config ~/.config/ai-shell/config.json
```

**Check logs**:
```bash
# macOS
cat ~/.config/ai-shell/daemon.error.log

# Linux
journalctl --user -u ai-shell-daemon -n 50
```

**Common Fixes**:
- Invalid configuration → Run `ai-shell-daemon --config <path>` to see validation errors
- Socket already in use → Remove stale socket: `rm /path/to/socket`
- Permissions → Ensure socket directory is writable

#### Can't Connect to Daemon

**Check socket exists**:
```bash
ls -la $(grep socketPath ~/.config/ai-shell/config.json | cut -d'"' -f4)
```

**Check daemon is running**:
```bash
# macOS
launchctl list | grep aishell

# Linux
systemctl --user status ai-shell-daemon
```

**Restart daemon**:
```bash
# macOS
launchctl stop com.aishell.daemon
launchctl start com.aishell.daemon

# Linux
systemctl --user restart ai-shell-daemon
```

#### Ollama Connection Errors

**Verify Ollama is running**:
```bash
curl http://localhost:11434/api/tags
```

**Check model is pulled**:
```bash
ollama list
```

**Pull missing model**:
```bash
ollama pull llama3.1:8b
```

### Performance Issues

**Slow Responses**:
1. Check Ollama performance: `ollama run llama3.1:8b "test"`
2. Enable cache: Set `enableCache: true`
3. Use faster model: Switch to `mistral:7b`
4. Check system resources: `top` or `htop`

**High Memory Usage**:
1. Reduce cache age: Set `maxCacheAge: 1`
2. Reduce memory age: Set `maxMemoryAge: 24`
3. Disable features: Set `enableRAG: false`, `enableCache: false`

## Maintenance

### Regular Maintenance Tasks

**Weekly**:
- Review daemon logs for errors
- Check disk space: `df -h ~/.config/ai-shell`
- Verify health: `ai_shell_health`

**Monthly**:
- Update Ollama: `ollama pull llama3.1:8b`
- Rotate logs (if not using systemd journal)
- Review and clean cache: `rm ~/.config/ai-shell/cache.json` (if needed)

**Quarterly**:
- Update AI Shell Assistant: `git pull && ./install-production.sh --production`
- Update dependencies: `brew upgrade` or `apt update && apt upgrade`
- Review configuration for optimization opportunities

### Backup

**What to Back Up**:
```bash
# Configuration
~/.config/ai-shell/config.json

# Memory and knowledge base
~/.config/ai-shell/memory.json
~/.config/ai-shell/embeddings.json

# Custom prompts (if modified)
~/.config/ai-shell/prompts.json
```

**Backup Script**:
```bash
#!/bin/bash
BACKUP_DIR="$HOME/backups/ai-shell/$(date +%Y%m%d)"
mkdir -p "$BACKUP_DIR"
cp ~/.config/ai-shell/*.json "$BACKUP_DIR/"
tar czf "$HOME/backups/ai-shell-$(date +%Y%m%d).tar.gz" "$BACKUP_DIR"
```

### Updates

**Update AI Shell Assistant**:
```bash
cd ~/path/to/ai-assistant-zsh
git pull
./install-production.sh --production --auto-start --quiet
exec zsh
```

**Update Ollama**:
```bash
# macOS
brew upgrade ollama

# Linux
curl -fsSL https://ollama.com/install.sh | sh
```

**Update Models**:
```bash
ollama pull llama3.1:8b
```

### Uninstall

**Complete Removal**:
```bash
# Stop daemon
# macOS
launchctl unload ~/Library/LaunchAgents/com.aishell.daemon.plist
rm ~/Library/LaunchAgents/com.aishell.daemon.plist

# Linux
systemctl --user stop ai-shell-daemon
systemctl --user disable ai-shell-daemon
rm ~/.config/systemd/user/ai-shell-daemon.service
systemctl --user daemon-reload

# Remove files
sudo rm /usr/local/bin/ai-shell-daemon
rm -rf ~/.config/ai-shell
rm -rf ~/.zsh/ai-shell

# Remove from .zshrc
sed -i.bak '/AI Shell Assistant/,+1d' ~/.zshrc
```

## Production Checklist

Before deploying to production:

- [ ] Run `./install-production.sh --production` (not `--dev`)
- [ ] Verify `logLevel: "info"` in config
- [ ] Confirm secure socket path (not `/tmp`)
- [ ] Test health check: `ai_shell_health`
- [ ] Verify auto-start works after reboot
- [ ] Test simplified syntax: `* list files`
- [ ] Review [SECURITY.md](SECURITY.md)
- [ ] Set up monitoring/alerting
- [ ] Document deployment specifics
- [ ] Create backup schedule
- [ ] Test disaster recovery procedure

## Support

- **Documentation**: See [README.md](README.md) for user guide
- **Security**: See [SECURITY.md](SECURITY.md) for security details
- **Configuration**: See [config/README.md](config/README.md) for config options
- **Issues**: https://github.com/yourusername/ai-assistant-zsh/issues
- **Discussions**: https://github.com/yourusername/ai-assistant-zsh/discussions

## License

See [LICENSE](LICENSE) file.

# Security Guide

This document describes the security model, considerations, and best practices for AI Shell Assistant.

## Table of Contents

- [Security Model](#security-model)
- [Threat Model](#threat-model)
- [Security Features](#security-features)
- [Best Practices](#best-practices)
- [Known Limitations](#known-limitations)
- [Reporting Security Issues](#reporting-security-issues)

## Security Model

### Design Principles

AI Shell Assistant is designed with these security principles:

1. **Least Privilege**: Runs as regular user, never requires root
2. **Defense in Depth**: Multiple layers of security controls
3. **Fail Secure**: Errors default to safe behavior (no execution)
4. **User Confirmation**: All commands require explicit user approval
5. **Isolation**: Uses Unix domain sockets for local-only communication
6. **Transparency**: All operations are logged and visible

### Trust Boundaries

```
┌─────────────────────────────────────────────────────────┐
│ User (Trusted)                                          │
│  ↓                                                      │
│ ZSH Shell (Trusted)                                     │
│  ↓                                                      │
│ AI Shell Assistant Daemon (Trusted)                     │
│  ↓                                                      │
│ Ollama API (Localhost - Trusted)                        │
│  ↓                                                      │
│ LLM Model (Trusted within limits - see below)           │
└─────────────────────────────────────────────────────────┘
```

**Key Points**:
- All components run in user space (no root required)
- Communication is local-only (Unix sockets)
- User must confirm all AI-generated commands
- No external network communication by default

## Threat Model

### In Scope

Threats we protect against:

1. **Command Injection**: Malicious commands in AI responses
   - **Mitigation**: Markdown filtering, user confirmation

2. **Unauthorized Access**: Other users accessing your daemon
   - **Mitigation**: Socket permissions (0600), user-specific paths

3. **Information Disclosure**: Sensitive data in logs or responses
   - **Mitigation**: Configurable logging, local-only operation

4. **Resource Exhaustion**: Daemon consuming excessive resources
   - **Mitigation**: Configurable limits, timeouts

### Out of Scope

Threats we do NOT protect against:

1. **Malicious User**: User with shell access is trusted
2. **Compromised Ollama**: We assume Ollama binary is trustworthy
3. **Model Poisoning**: We assume Ollama models are from trusted sources
4. **Physical Access**: Physical attacker with system access
5. **Root Compromise**: Root-level malware can bypass all protections

### Trust Assumptions

We assume:
- ✅ User is not malicious
- ✅ Ollama binary is authentic (downloaded from ollama.com)
- ✅ Operating system is not compromised
- ✅ Model files are from trusted sources
- ❌ AI model outputs are NOT fully trusted (hence user confirmation)

## Security Features

### 1. Command Confirmation

**What**: Every AI-generated command requires explicit user approval

**Why**: AI models can be tricked or make mistakes

**How**:
```zsh
* delete all log files
# Shows:
Suggested commands:
---
find . -name "*.log" -type f -delete
---
Execute these commands? (y/n)
```

**Security Impact**: Prevents accidental/malicious command execution

### 2. Socket Permissions

**What**: Unix socket has 0600 permissions (owner read/write only)

**Why**: Prevents other users from sending commands to your daemon

**How**: Automatically set in `SocketServer.swift:90`
```swift
chmod(socketPath, 0o600)
```

**Security Impact**: Prevents privilege escalation and unauthorized access

### 3. User-Specific Paths

**What**: Socket path includes user ID

**Why**: Prevents socket conflicts and cross-user access attempts

**How**: `install-production.sh` uses:
- macOS: `${TMPDIR}ai-shell-${UID}.sock`
- Linux: `/run/user/${UID}/ai-shell.sock`

**Security Impact**: Isolation between users on multi-user systems

### 4. Input Validation

**What**: All configuration values are validated before use

**Why**: Prevents injection attacks via config files

**How**: `Configuration.validate()` checks:
- Log levels are valid strings
- URLs are well-formed
- Numeric values are in range
- Required fields are non-empty

**Security Impact**: Reduces attack surface from malicious configs

### 5. Markdown Filtering

**What**: Strip markdown code blocks from AI responses

**Why**: Prevents command injection via markdown formatting

**How**: `RequestHandler.swift:138-149` filters lines starting with ` ``` `

**Security Impact**: Prevents sneaking malicious commands into responses

### 6. Logging Controls

**What**: Configurable logging levels and output destinations

**Why**: Balance between audit trail and information disclosure

**How**: Set `logLevel` in config:
- `error`: Minimal logging (production)
- `info`: Normal operations (default)
- `warning`: Warnings and errors
- `debug`: Verbose (development only)

**Security Impact**: Prevents sensitive data leakage while maintaining audit trail

### 7. No External Network Access

**What**: All communication is local-only (Unix sockets, localhost HTTP)

**Why**: Reduces attack surface and prevents data exfiltration

**How**:
- Daemon-to-client: Unix domain socket
- Daemon-to-Ollama: `http://localhost:11434`

**Security Impact**: Network attacks are not possible

## Best Practices

### For Users

1. **Review Commands Before Execution**
   - Always read AI-generated commands carefully
   - Understand what each command does
   - Use `Ctrl+C` to cancel if unsure

2. **Keep Software Updated**
   - Update AI Shell Assistant regularly
   - Keep Ollama up to date
   - Update OS and dependencies

3. **Use Appropriate Log Levels**
   - Production: `info` or `warning`
   - Development: `debug`
   - Never disable logging entirely

4. **Protect Configuration Files**
   - Keep `~/.config/ai-shell/config.json` permissions at 644
   - Don't commit config files with sensitive data
   - Review config changes carefully

5. **Use Strong Prompts**
   - Be specific in your requests
   - Avoid ambiguous language
   - Example: "delete all log files in ./logs older than 30 days" not "clean up"

### For System Administrators

1. **Multi-User Systems**
   - Each user should install individually
   - Monitor daemon resource usage
   - Consider disk quotas for cache/memory storage

2. **Monitoring**
   - Enable logging in production
   - Monitor daemon health: `ai_shell_health`
   - Set up alerts for daemon failures

3. **Access Control**
   - Ensure proper file permissions
   - Use AppArmor/SELinux if available
   - Restrict who can install Ollama models

4. **Network Security**
   - Keep Ollama on localhost only
   - If remote Ollama: use TLS, firewall rules
   - Consider network segmentation

5. **Backup and Recovery**
   - Back up configuration regularly
   - Back up memory/RAG databases
   - Test restoration procedures

### For Developers

1. **Input Validation**
   - Validate all user inputs
   - Sanitize data before logging
   - Use parameterized queries (when applicable)

2. **Error Handling**
   - Don't expose sensitive info in errors
   - Log errors with context
   - Fail securely (no execution on error)

3. **Code Review**
   - Review security-critical changes carefully
   - Test error paths
   - Consider edge cases

4. **Dependencies**
   - Keep dependencies updated
   - Review dependency security advisories
   - Minimize dependency count

## Known Limitations

### 1. AI Model Trustworthiness

**Issue**: AI models can be tricked or make mistakes

**Impact**: May generate incorrect or dangerous commands

**Mitigation**: User confirmation required for all commands

**Residual Risk**: User may not understand command implications

### 2. Local Privilege Escalation

**Issue**: User with shell access is already privileged

**Impact**: Daemon runs with user's full permissions

**Mitigation**: None needed - user is trusted at this level

**Residual Risk**: None (by design)

### 3. Command Injection in AI Responses

**Issue**: AI might include shell metacharacters in responses

**Impact**: Unintended command interpretation

**Mitigation**: Markdown filtering, user confirmation, careful prompting

**Residual Risk**: User might not notice subtle injection

**Example**:
```bash
# Malicious prompt response might try:
rm important.txt ; echo "File deleted"

# But user sees this clearly and can reject it
```

### 4. Information Disclosure via Logs

**Issue**: Logs may contain sensitive information

**Impact**: Secrets visible in log files

**Mitigation**: Configurable log levels, secure log storage

**Residual Risk**: Debug logs may expose data

**Recommendation**: Use `info` or higher in production

### 5. Resource Exhaustion

**Issue**: Daemon could consume excessive resources

**Impact**: System slowdown or DoS

**Mitigation**: Ollama has built-in rate limiting, daemon timeouts

**Residual Risk**: Large models + many requests = high resource use

**Recommendation**: Monitor resource usage, use resource limits

### 6. Ollama Security

**Issue**: We rely on Ollama's security

**Impact**: Ollama vulnerabilities affect us

**Mitigation**: Keep Ollama updated, use official distributions

**Residual Risk**: Ollama zero-day vulnerabilities

**Recommendation**: Subscribe to Ollama security advisories

## Security Hardening

### Advanced Security Measures

#### 1. AppArmor Profile (Linux)

Create `/etc/apparmor.d/usr.local.bin.ai-shell-daemon`:

```
#include <tunables/global>

/usr/local/bin/ai-shell-daemon {
  #include <abstractions/base>

  # Allow reading config
  owner @{HOME}/.config/ai-shell/** r,

  # Allow socket
  owner @{HOME}/.config/ai-shell/*.sock rw,

  # Allow Ollama access
  network inet stream,

  # Deny everything else
  deny /etc/** w,
  deny /sys/** w,
  deny /proc/** w,
}
```

Enable:
```bash
sudo apparmor_parser -r /etc/apparmor.d/usr.local.bin.ai-shell-daemon
```

#### 2. Systemd Hardening (Linux)

Edit `~/.config/systemd/user/ai-shell-daemon.service`:

```ini
[Service]
# Resource limits
MemoryMax=512M
CPUQuota=50%
TasksMax=10

# Security
NoNewPrivileges=yes
PrivateTmp=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=%h/.config/ai-shell

# Network
RestrictAddressFamilies=AF_UNIX AF_INET
```

#### 3. Audit Logging

Enable command audit trail:

```bash
# Add to ~/.zshrc
function ai_shell_audit() {
    echo "$(date -Iseconds) [AI_SHELL] $*" >> ~/.ai_shell_audit.log
}

# Wrap AI commands
function *() {
    ai_shell_audit "TASK: $*"
    command * "$@"
}
```

#### 4. Read-Only Configuration

Prevent config tampering:

```bash
chmod 444 ~/.config/ai-shell/config.json
chattr +i ~/.config/ai-shell/config.json  # Linux only
```

## Reporting Security Issues

### What to Report

Report security vulnerabilities such as:
- Command injection bypassing confirmation
- Unauthorized access to daemon
- Information disclosure issues
- Privilege escalation vulnerabilities

### How to Report

**DO NOT** open public GitHub issues for security vulnerabilities.

Instead:
1. Email: security@example.com (use GPG if possible)
2. Include:
   - Description of vulnerability
   - Steps to reproduce
   - Impact assessment
   - Suggested fix (if any)

### Response Timeline

- **24 hours**: Initial acknowledgment
- **7 days**: Initial assessment
- **30 days**: Fix development and testing
- **90 days**: Public disclosure (coordinated)

### Hall of Fame

We recognize security researchers who responsibly disclose vulnerabilities:

- (Your name could be here!)

## Security Checklist

Before production deployment:

- [ ] Run `./install-production.sh --production` (not `--dev`)
- [ ] Verify socket path includes user ID
- [ ] Confirm socket permissions are 0600
- [ ] Set `logLevel: "info"` or higher (not debug)
- [ ] Verify Ollama is localhost-only
- [ ] Enable auto-start with service manager
- [ ] Test command confirmation works
- [ ] Review [README-PRODUCTION.md](README-PRODUCTION.md)
- [ ] Set up monitoring/alerting
- [ ] Create backup procedures
- [ ] Document incident response plan

## Compliance Considerations

### GDPR

- AI Shell Assistant processes data locally
- No data is sent to external services
- User controls all data (config, memory, cache)
- Right to erasure: `rm -rf ~/.config/ai-shell`

### SOC 2

- Access Controls: Socket permissions, user isolation
- Audit Logging: Configurable logging levels
- Data Encryption: Unix socket communication (local only)
- Incident Response: See "Reporting Security Issues"

### Industry Best Practices

- OWASP Top 10: Input validation, output encoding
- CWE: Adherence to common weakness enumeration
- NIST: Principle of least privilege, defense in depth

## References

- [OWASP Secure Coding Practices](https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/)
- [CIS Security Benchmarks](https://www.cisecurity.org/cis-benchmarks/)
- [Ollama Security](https://ollama.com/security)
- [Swift Security](https://swift.org/security/)

## License

See [LICENSE](LICENSE) file.

---

**Last Updated**: 2025-01-18
**Version**: 1.0.0

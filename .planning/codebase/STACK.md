# Technology Stack

**Analysis Date:** 2026-01-23

## Languages

**Primary:**
- Swift 5.9+ - All core application code, CLI, daemon, and libraries

## Runtime

**Environment:**
- macOS 13.0+ (Sonoma and later)
- Architecture: Universal (Apple Silicon arm64 + Intel x86_64)

**Package Manager:**
- Swift Package Manager (SPM)
- Lockfile: `Package.resolved` (present)

## Frameworks

**Core:**
- AsyncHTTPClient 1.19.0+ - HTTP client for Ollama API communication
- swift-log 1.5.0+ - Structured logging throughout application
- swift-argument-parser 1.2.0+ - CLI argument parsing for commands
- swift-crypto 3.0.0+ - Cryptographic hashing for cache keys (SHA256)

**Platform-Specific:**
- Darwin (macOS) / Glibc (Linux) - Platform-specific system calls for Unix domain sockets

**Concurrency:**
- Swift Concurrency (async/await) - Actor-based concurrent patterns
- NIOCore - Async HTTP primitives from Nio (dependency of AsyncHTTPClient)
- NIOHTTP1 - HTTP protocol handling

## Key Dependencies

**Critical:**
- async-http-client 1.19.0+ - Communicates with Ollama API (generate, chat, embeddings endpoints)
- swift-log 1.5.0+ - Required for all logging throughout the system
- ArgumentParser 1.2.0+ - Powers CLI command parsing for `ai` and `ai-shell-daemon` executables

**Infrastructure:**
- swift-crypto 3.0.0+ - SHA256 hashing for cache key generation
- NIO packages (pulled via async-http-client) - Event-driven networking foundation

## Configuration

**Environment:**
- Configuration via JSON file: `config.example.json`
- Loaded from path specified in daemon CLI or defaults to user-provided path
- Falls back to defaults if configuration file missing or invalid
- Environment-specific setup: Default socket at `/tmp/ai-shell.sock`

**Build:**
- Package.swift manifest defines all targets and dependencies
- Swift tools version: 5.9 minimum
- Build output: Universal binaries for macOS

## Platform Requirements

**Development:**
- Xcode 14+ with Swift 5.9+
- macOS 13.0 SDK
- Swift Package Manager (included with Xcode)

**Production:**
- macOS 13.0 or later
- Ollama runtime (external dependency, not bundled)
  - Ollama accessible at configurable URL (default: http://localhost:11434)
  - Must have compatible model installed (default: llama3.1:8b)

## Notable Stack Characteristics

**No External Databases:**
- All storage is file-based (JSON)
- Memory store: `~/.config/ai-shell/memory.json`
- RAG embeddings: `~/.config/ai-shell/embeddings.json`
- Response cache: `~/.config/ai-shell/cache.json`

**Pure Swift Implementation:**
- No Objective-C dependencies
- Uses standard Darwin/POSIX APIs for socket communication
- No third-party JSON libraries (uses Foundation's Codable)

**Actor-Based Concurrency:**
- `OllamaClient` - HTTP communication to Ollama
- `MemoryStore` - Session and memory management
- `EmbeddingStore` - Vector storage and RAG operations
- `ResponseCache` - Response caching with SHA256 hashing
- `SocketServer` - Unix domain socket server

---

*Stack analysis: 2026-01-23*

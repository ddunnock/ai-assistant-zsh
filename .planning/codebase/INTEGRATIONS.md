# External Integrations

**Analysis Date:** 2026-01-23

## APIs & External Services

**LLM / AI Inference:**
- Ollama - Local LLM inference engine
  - SDK/Client: Custom `OllamaClient` in `Sources/AIShellCore/Clients/OllamaClient.swift`
  - API Base URL: Configurable via config, default `http://localhost:11434`
  - Authentication: None (local service)
  - Endpoints used:
    - `/api/generate` - Text completion (streaming and non-streaming)
    - `/api/chat` - Multi-turn chat completion
    - `/api/tags` - List available models
    - `/api/embeddings` - Generate text embeddings for RAG

## Data Storage

**Databases:**
- None (No traditional database)

**Local File Storage:**
- JSON-based persistence only
- Memory Store: `~/.config/ai-shell/memory.json`
  - Stores: Session contexts, conversation history, command memory, long-term facts
  - Type: Local filesystem JSON
  - Client: Built-in `MemoryStore` actor (`Sources/AIShellCore/Memory/MemoryStore.swift`)
  - Config: `memoryStoragePath` in configuration (optional override)

- Embeddings Store: `~/.config/ai-shell/embeddings.json`
  - Stores: Vector embeddings for RAG (retrieval-augmented generation)
  - Documents indexed: Man pages, READMEs, help text, command examples, project docs
  - Type: Local filesystem JSON
  - Client: Built-in `EmbeddingStore` actor (`Sources/AIShellCore/RAG/EmbeddingStore.swift`)
  - Config: `ragStoragePath` in configuration (optional override)

- Response Cache: `~/.config/ai-shell/cache.json`
  - Stores: Cached LLM responses with SHA256 keys
  - TTL: 7 days (configurable via `maxCacheAge`)
  - Max entries: 500 (pruned by hit count + recency when exceeded)
  - Type: Local filesystem JSON
  - Client: Built-in `ResponseCache` actor (`Sources/AIShellCore/Cache/ResponseCache.swift`)
  - Config: `cacheStoragePath` in configuration (optional override)

**File Storage:**
- Local filesystem only (no cloud storage)
- Configuration directory: `~/.config/ai-shell/`
- Socket communication file: `/tmp/ai-shell.sock` (Unix domain socket)

**Caching:**
- In-memory actor-based caching (ResponseCache)
- Persistent JSON file caching (7-day TTL)
- Embedding similarity caching via vector store

## Authentication & Identity

**Auth Provider:**
- Custom (None required)
  - No authentication layer implemented
  - Communication between CLI and daemon via Unix domain socket (local machine only)
  - Ollama integration assumes local service with no auth

## Monitoring & Observability

**Error Tracking:**
- None (No external error tracking service)

**Logs:**
- File-based logging via swift-log
- Logger factory: `LoggerFactory.create(category:)` in `Sources/AIShellCore/Utilities/Logger.swift`
- Log categories: ollama, memory, rag, cache, socket, and component-specific loggers
- Structured logging with metadata (key-value pairs)
- Output: stdout/stderr during development; daemon logs to file or stdout

## CI/CD & Deployment

**Hosting:**
- Local macOS machines only (no remote deployment)
- Installation via shell script: `install.sh` (creates symlinks, installs binaries)

**CI Pipeline:**
- GitHub Actions workflow: `.github/workflows/ci.yml`
- Build targets: AIShellCLI, AIShellDaemon, AIShellCore
- Test target: AIShellTests
- Runs on: macOS runners

## Environment Configuration

**Required env vars:**
- None strictly required; all configuration via JSON file
- Optional: Custom paths for socket, storage directories via config file

**Configuration file (JSON):**
Located at user-specified path, falls back to defaults:

```json
{
  "socketPath": "/tmp/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "info",
  "enableMemory": true,
  "enableRAG": true,
  "enableCache": true,
  "enableStreaming": false,
  "memoryStoragePath": null,
  "ragStoragePath": null,
  "cacheStoragePath": null,
  "promptsStoragePath": null,
  "maxMemoryAge": 24,
  "maxCacheAge": 7,
  "ragMinSimilarity": 0.6
}
```

**Secrets location:**
- No secrets stored in configuration
- No API keys or credentials required

## Webhooks & Callbacks

**Incoming:**
- None

**Outgoing:**
- None

## System Dependencies

**macOS-specific:**
- Darwin framework for socket operations (platform abstraction in `Sources/AIShellCore/Server/SocketServer.swift`)
- BSD socket API (AF_UNIX, SOCK_STREAM)
- File system access via FileManager

**External Runtime:**
- Ollama service must be running and accessible at configured URL
  - Default: localhost:11434
  - Must have compatible LLM model available

## Data Flow & Communication

**CLI to Daemon:**
- Unix domain socket (`/tmp/ai-shell.sock` by default)
- Request/Response protocol: JSON-based (custom protocol in `Sources/AIShellCore/Server/Protocol.swift`)
- Async bidirectional communication over socket stream

**Daemon to Ollama:**
- HTTP REST API via AsyncHTTPClient
- Async/await patterns with configurable timeouts
- Streaming support for long-running generation tasks

**Memory & Cache Persistence:**
- Periodic saves to disk after modifications
- Lazy loads on daemon startup
- JSON encoding with ISO8601 timestamps

---

*Integration audit: 2026-01-23*

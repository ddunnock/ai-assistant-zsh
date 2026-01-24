# Architecture

**Analysis Date:** 2026-01-23

## Pattern Overview

**Overall:** Client-Server with Daemon Architecture

**Key Characteristics:**
- **Process separation**: CLI client communicates with background daemon via Unix domain socket
- **Layered request handling**: Pluggable request handlers with middleware-style enhancement
- **Phase-based feature implementation**: Core Phase 1 (command suggestions/explanations) with Phase 2 features (memory, RAG, caching) conditionally loaded
- **Actor-based concurrency**: Uses Swift's structured concurrency with actor model for thread safety
- **Streaming-ready protocol**: Length-prefixed message framing supporting future streaming enhancements

## Layers

**CLI Layer:**
- Purpose: User-facing command-line interface with subcommands for different operations
- Location: `Sources/AIShellCLI/`
- Contains: Command definitions (suggest, explain, task, remember, recall, index, search), daemon management, socket client
- Depends on: AIShellCore (models, socket protocol)
- Used by: User shell integration (zsh, bash)

**Socket Communication Layer:**
- Purpose: IPC transport using Unix domain sockets with length-prefixed framing
- Location: `Sources/AIShellCore/Server/SocketServer.swift`, `Sources/AIShellCLI/SocketClient.swift`
- Contains: Server-side connection handling, client connection logic, message framing protocol
- Depends on: Darwin/Glibc (BSD socket API), Protocol definitions
- Used by: Daemon service and CLI commands

**Request Handling Layer:**
- Purpose: Process requests and generate responses with optional feature enhancement
- Location: `Sources/AIShellCore/Server/EnhancedRequestHandler.swift`, `Sources/AIShellCore/Server/RequestHandler.swift`
- Contains: Request routing, response generation, feature integration (memory, RAG, caching)
- Depends on: OllamaClient, MemoryStore, EmbeddingStore, ResponseCache, PromptTemplates
- Used by: SocketServer

**Data Models Layer:**
- Purpose: Serializable request/response structures and domain models
- Location: `Sources/AIShellCore/Models/`
- Contains: Request types, Payload structures, Response definitions, error types
- Depends on: Foundation (Codable)
- Used by: All layers

**Ollama Integration Layer:**
- Purpose: Communication with local Ollama LLM via HTTP
- Location: `Sources/AIShellCore/Clients/OllamaClient.swift`
- Contains: HTTP client, API request/response models, health checks, generation/chat endpoints
- Depends on: AsyncHTTPClient, NIO
- Used by: Request handlers, embedding store

**Phase 2 Enhancement Layers:**
- **Memory Store** (`Sources/AIShellCore/Memory/MemoryStore.swift`): Session context, conversation history, long-term facts
- **Embedding/RAG Store** (`Sources/AIShellCore/RAG/EmbeddingStore.swift`): Document embeddings, semantic search, retrieval
- **Response Cache** (`Sources/AIShellCore/Cache/ResponseCache.swift`): Deduplication of identical requests, cache expiration
- **Prompt Templates** (`Sources/AIShellCore/Prompts/PromptTemplates.swift`): Customizable system prompts and instruction templates

**Daemon Orchestration Layer:**
- Purpose: Lifecycle management and feature initialization
- Location: `Sources/AIShellDaemon/DaemonService.swift`
- Contains: Start/stop sequencing, Phase 2 component initialization, signal handling, PID file management
- Depends on: Configuration, all core components
- Used by: Daemon CLI entry point

**Utilities Layer:**
- Purpose: Cross-cutting infrastructure
- Location: `Sources/AIShellCore/Utilities/`
- Contains: Logging (AppLogger, LoggerFactory), date formatting, input validation, command safety checking, string extensions
- Depends on: Logging package, Foundation
- Used by: All layers

## Data Flow

**Request Processing Pipeline:**

1. **User Invokes Command** → Shell script calls `ai suggest "command"`
2. **CLI Startup** → `AI.swift` routes to SuggestCommand
3. **DaemonManager** → Checks if daemon running; starts if needed
4. **Socket Connection** → SocketClient connects to Unix domain socket at `/tmp/ai-shell.sock`
5. **Request Serialization** → Command parameters encoded into Request JSON with metadata (cwd, git branch, etc.)
6. **Length-Prefixed Framing** → FramedMessage wraps JSON with 4-byte big-endian length prefix
7. **Socket Write** → Entire framed message sent to daemon
8. **Daemon Receives** → SocketServer accepts connection, reads length prefix, reads exact message bytes
9. **Message Deserialization** → JSON decoded into Request struct with flexible ISO8601 date handling
10. **Request Handling** → EnhancedRequestHandler processes request:
    - Check cache (if enabled) → Return cached response if hit
    - Load context (memory, templates) → Enrich prompt with session history
    - Generate response → Call OllamaClient.generate() or .chat() with formatted prompt
    - Store results → Update memory, cache, RAG indices (if enabled)
11. **Response Serialization** → Response struct encoded to JSON
12. **Framed Response** → FramedMessage wraps response JSON
13. **Socket Write** → Daemon sends framed response
14. **Client Receives** → SocketClient reads length prefix, reads message, deserializes
15. **Display Results** → CLI command displays suggestion/explanation to user

**Conversation State Flow (When Memory Enabled):**

1. MemoryStore.startSession() creates SessionContext with UUID
2. Each turn: userMessage + assistantResponse added to SessionContext.conversationHistory
3. On handler completion, MemoryStore.addConversationTurn() persists turn
4. Session saved to disk at shutdown via savePhase2Components()

**Semantic Search Flow (When RAG Enabled):**

1. User calls `ai index <file> <content>`
2. EmbeddingStore.add() calls OllamaClient to generate embedding for content
3. EmbeddedDocument created with embedding vector, metadata (source, tags, importance)
4. Document persisted to embeddings.json
5. Later, user calls `ai search <query>`
6. EmbeddingStore.search() generates embedding for query
7. Cosine similarity computed against all stored embeddings
8. Top-K results returned based on similarity threshold

## State Management

**Memory State:**
- SessionContext: In-memory during daemon run, persisted to `~/.config/ai-shell/memory.json` at shutdown
- MemoryStore is an actor, ensuring thread-safe access to session data
- Long-term memories survive daemon restarts; session memory cleared on new daemon start

**Cache State:**
- ResponseCache: In-memory dictionary with SHA256-based keys
- Entries expire after 7 days (configurable)
- Persisted to `~/.config/ai-shell/cache.json` at shutdown
- Size-bounded at 500 entries; LRU-style eviction on overflow

**RAG State:**
- EmbeddingStore: In-memory vector collection
- Embeddings persisted to `~/.config/ai-shell/embeddings.json` with full content
- Built incrementally as users index documents
- Similarity threshold (ragMinSimilarity in config) controls search results

**Configuration State:**
- Loaded from `~/.config/ai-shell/config.json` (if exists) or uses defaults
- Feature flags (enableMemory, enableRAG, enableCache) control which layers are initialized
- Configurable storage paths allow custom locations for persistent data

## Key Abstractions

**RequestHandling Protocol:**
- Purpose: Abstract interface for processing requests
- Examples: `Sources/AIShellCore/Server/RequestHandling.swift`
- Pattern: Adopted by EnhancedRequestHandler and RequestHandler; allows swapping implementations
- Methods: `handle(_ request: Request) -> Response`

**RequestType Enum:**
- Purpose: Dispatch key for routing different request types
- Location: `Sources/AIShellCore/Models/Request.swift`
- Cases: suggest, explain, task, health, remember, forget, recall, index, search
- Enables extensible command set without modifying core handler

**Response Status Enum:**
- Purpose: Indicate request outcome (success, error, partial)
- Location: `Sources/AIShellCore/Models/Response.swift`
- Allows future support for streaming (partial status for in-progress responses)

**Actor Pattern:**
- DaemonService: Coordinates lifecycle and Phase 2 components
- SocketServer: Manages connections and accepts new connections
- OllamaClient: Serializes HTTP requests to single LLM model
- EnhancedRequestHandler: Processes requests sequentially
- MemoryStore: Thread-safe session/memory access
- EmbeddingStore: Thread-safe embedding operations
- ResponseCache: Thread-safe cache operations

**Configuration Merging:**
- Default configuration in code (`Configuration.default`)
- Optional JSON file merge: partial configs override defaults without requiring all keys
- Pattern allows safe configuration evolution

## Entry Points

**CLI Entry Point:**
- Location: `Sources/AIShellCLI/AI.swift`
- Triggers: User runs `ai` command with subcommand
- Responsibilities: Parse arguments (via ArgumentParser), route to appropriate command struct

**Daemon Entry Point:**
- Location: `Sources/AIShellDaemon/CLI.swift`
- Triggers: DaemonManager spawns daemon process with `ai-shell-daemon start`
- Responsibilities: Load configuration, create DaemonService, call run()

**Socket Server Entry Point:**
- Location: `Sources/AIShellCore/Server/SocketServer.swift`
- Triggers: DaemonService.start() instantiates and calls start()
- Responsibilities: Create Unix socket, bind, listen, accept connections in async loop

**SocketServer.Connection Entry Point:**
- Location: `Sources/AIShellCore/Server/SocketServer.swift` (private class)
- Triggers: SocketServer.acceptConnections() creates for each incoming connection
- Responsibilities: Read framed messages, deserialize, invoke requestHandler, send response

## Error Handling

**Strategy:** Three-level error propagation

**Level 1 - Socket Errors:**
- Location: Connection.readExactly(), writeAll()
- Handling: Log error, close connection, continue accepting
- Recovery: Connection-level; other connections unaffected
- Types: Socket read/write failures, EAGAIN/EWOULDBLOCK (non-blocking retries)

**Level 2 - Message Processing Errors:**
- Location: Connection.processMessage()
- Handling: Catch JSON decode/encode errors, create error Response, send back to client
- Recovery: Send error response with code/message; connection stays open for next request
- Types: Invalid JSON, type mismatch, decode strategy failures

**Level 3 - Request Handler Errors:**
- Location: EnhancedRequestHandler.handle()
- Handling: Catch exceptions from processRequest(), return error Response
- Recovery: Graceful degradation; log error, return structured error response
- Types: Ollama connection failures, cache/memory I/O errors, validation failures

**Error Response Pattern:**
```swift
Response.error(
    requestId: request.id,
    code: "ERROR_TYPE",
    message: "Human-readable explanation"
)
```

**Validation Layers:**
- InputValidator: Command/query string validation (in Utilities)
- CommandSafetyChecker: Dangerous command detection (in Utilities)
- Ollama health check: Verify LLM availability at daemon startup

## Cross-Cutting Concerns

**Logging:**
- Unified AppLogger wraps Logging package + os.log (for Console.app visibility)
- Categories: daemon, socket, handler, ollama, cache, memory, rag
- Levels: debug (detailed flow), info (operations), warning (recoverable issues), error (failures)
- Pattern: `LoggerFactory.create(category: "component")` across all modules

**Validation:**
- Command safety: CommandSafetyChecker.swift detects destructive patterns (rm -rf, etc.)
- Input validation: InputValidator.swift checks length, character sets, injection attempts
- Protocol version checking: ProtocolVersion.swift enforces compatibility

**Authentication:**
- None: Unix socket permissions (0o600) limit access to owner only
- No remote network exposure: Socket file in /tmp is local-only

**Concurrency:**
- Actor model ensures thread-safe access to shared state
- Sendable constraint on data models allows safe passing across tasks
- withCheckedContinuation used for signal-based shutdown coordination

**Serialization:**
- Request/Response use Codable protocol for automatic JSON encoding/decoding
- Custom date strategy (DateCoding.flexibleISO8601) handles fractional seconds
- All models conform to Sendable for actor compatibility

---

*Architecture analysis: 2026-01-23*

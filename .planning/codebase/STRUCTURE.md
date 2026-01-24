# Codebase Structure

**Analysis Date:** 2026-01-23

## Directory Layout

```
AIShellAssistant/
├── Sources/                    # Main source code
│   ├── AIShellCLI/            # CLI executable target
│   │   ├── AI.swift           # Main CLI entry point with subcommands
│   │   ├── Commands/          # Command implementations
│   │   ├── DaemonManager.swift
│   │   └── SocketClient.swift
│   ├── AIShellDaemon/         # Daemon executable target
│   │   ├── CLI.swift          # Daemon CLI entry point
│   │   ├── Configuration.swift
│   │   └── DaemonService.swift
│   └── AIShellCore/           # Shared library target
│       ├── Cache/             # Response caching
│       ├── Clients/           # External service clients (Ollama)
│       ├── Memory/            # Session/long-term memory
│       ├── Models/            # Serializable data models
│       ├── Prompts/           # Prompt template system
│       ├── RAG/               # Retrieval-augmented generation (embeddings)
│       ├── Server/            # Socket server and request handling
│       └── Utilities/         # Logging, validation, helpers
├── Tests/                      # Test suite
│   └── AIShellTests/          # Unit tests
├── docs/                       # Documentation
├── zsh/                        # ZSH shell integration
├── .github/                    # GitHub Actions CI/CD
├── Package.swift              # Swift Package manifest
├── install.sh                 # Installation script
└── README.md                  # Project overview
```

## Directory Purposes

**Sources/AIShellCLI:**
- Purpose: User-facing command-line interface
- Contains: CLI argument parsing, command routing, daemon lifecycle management
- Key files: `AI.swift` (main), `Commands/` (subcommands), `SocketClient.swift` (IPC)

**Sources/AIShellCLI/Commands:**
- Purpose: Individual command implementations
- Contains: SuggestCommand, ExplainCommand, TaskCommand, StartCommand, StopCommand, RestartCommand, DoctorCommand, LogsCommand, ConfigCommand
- Pattern: Each file exports AsyncParsableCommand struct using swift-argument-parser

**Sources/AIShellDaemon:**
- Purpose: Background daemon process
- Contains: Daemon lifecycle, feature initialization, configuration loading
- Key files: `DaemonService.swift` (orchestrator), `Configuration.swift` (config loading), `CLI.swift` (entry point)

**Sources/AIShellCore:**
- Purpose: Shared business logic library
- Contains: Server, clients, data models, feature implementations
- Products: Imported by both CLI and Daemon targets; distributed as library

**Sources/AIShellCore/Server:**
- Purpose: Socket-based IPC and request handling
- Key files:
  - `SocketServer.swift`: Unix domain socket server with BSD socket API
  - `EnhancedRequestHandler.swift`: Main request processing with Phase 2 features
  - `RequestHandler.swift`: Basic request processing (non-enhanced)
  - `RequestHandling.swift`: Protocol definition
  - `Protocol.swift`: Message framing (FramedMessage, ProtocolVersion)

**Sources/AIShellCore/Clients:**
- Purpose: External service integration
- Key files:
  - `OllamaClient.swift`: HTTP client for local Ollama LLM
  - `OllamaModels.swift`: Ollama API request/response models

**Sources/AIShellCore/Models:**
- Purpose: Serializable domain models
- Key files:
  - `Request.swift`: Client→Server request with RequestType enum and Payload
  - `Response.swift`: Server→Client response with Status and error handling
  - `ErrorTypes.swift`: AIShellError enum for domain errors

**Sources/AIShellCore/Memory:**
- Purpose: Session and long-term memory management
- Key files:
  - `MemoryStore.swift`: SessionContext, MemoryEntry, MemoryType enum, conversation history

**Sources/AIShellCore/Cache:**
- Purpose: Response deduplication and caching
- Key files:
  - `ResponseCache.swift`: CachedResponse entries, cache hit/miss logic, expiration

**Sources/AIShellCore/RAG:**
- Purpose: Semantic search via embeddings
- Key files:
  - `EmbeddingStore.swift`: EmbeddedDocument, DocumentMetadata, DocumentSource, similarity search

**Sources/AIShellCore/Prompts:**
- Purpose: Customizable prompt templates
- Key files:
  - `PromptTemplates.swift`: System prompts, instruction templates, customization

**Sources/AIShellCore/Utilities:**
- Purpose: Cross-cutting infrastructure
- Key files:
  - `Logger.swift`: AppLogger, LoggerFactory (unified logging)
  - `InputValidator.swift`: Input validation (length, characters, injection)
  - `CommandSafetyChecker.swift`: Dangerous command detection
  - `DateFormatters.swift`: ISO8601 date handling
  - `Extensions.swift`: String/Date helpers
  - `DateFormatters.swift`: Custom date coding strategy

**Tests/AIShellTests:**
- Purpose: Unit test suite
- Key files:
  - `OllamaClientTests.swift`: HTTP client tests
  - `RequestHandlerTests.swift`: Request processing tests
  - `ProtocolTests.swift`: Message framing tests
  - `CommandSafetyCheckerTests.swift`: Safety validation tests
  - `InputValidatorTests.swift`: Input validation tests
  - `MockOllamaClient.swift`: Test double for OllamaClient

**docs/:**
- Purpose: Project documentation
- Contains: Architecture diagrams, API specs, deployment guides

**zsh/:**
- Purpose: Shell integration
- Contains: `ai-assistant.zsh` plugin for ZSH completion and shortcuts

**.github/:**
- Purpose: CI/CD automation
- Contains: GitHub Actions workflows for testing and builds

## Key File Locations

**Entry Points:**
- `Sources/AIShellCLI/AI.swift`: CLI main entry point (@main struct AI)
- `Sources/AIShellDaemon/CLI.swift`: Daemon entry point
- `Sources/AIShellDaemon/DaemonService.swift`: Daemon orchestrator (run() method)

**Configuration:**
- `Sources/AIShellDaemon/Configuration.swift`: Configuration loading and defaults
- `~/.config/ai-shell/config.json`: User configuration file (optional)

**Core Logic:**
- `Sources/AIShellCore/Server/EnhancedRequestHandler.swift`: Main request processing
- `Sources/AIShellCore/Server/SocketServer.swift`: Socket server implementation
- `Sources/AIShellCore/Clients/OllamaClient.swift`: LLM client

**Data Models:**
- `Sources/AIShellCore/Models/Request.swift`: Inbound request format
- `Sources/AIShellCore/Models/Response.swift`: Outbound response format
- `Sources/AIShellCore/Models/ErrorTypes.swift`: Error domain

**Phase 2 Features:**
- `Sources/AIShellCore/Memory/MemoryStore.swift`: Conversation memory
- `Sources/AIShellCore/RAG/EmbeddingStore.swift`: Semantic search
- `Sources/AIShellCore/Cache/ResponseCache.swift`: Response deduplication
- `Sources/AIShellCore/Prompts/PromptTemplates.swift`: Custom prompts

**Shell Integration:**
- `zsh/ai-assistant.zsh`: ZSH plugin for interactive shell hooks

**Build & Package:**
- `Package.swift`: Swift Package manifest (targets, dependencies)
- `Package.resolved`: Dependency lock file
- `build.sh`: Build script for local development

## Naming Conventions

**Files:**
- PascalCase: Swift source files (`DaemonService.swift`, `OllamaClient.swift`)
- Descriptive: Component + purpose (`ResponseCache.swift`, `CommandSafetyChecker.swift`)
- Commands: PascalCase + "Command" suffix (`SuggestCommand.swift`, `ExplainCommand.swift`)
- Tests: PascalCase + "Tests" suffix (`OllamaClientTests.swift`)

**Directories:**
- PascalCase or lowercase: Features in subdirectories (`Memory/`, `RAG/`, `Clients/`)
- Functional grouping: By layer or concern (Server, Models, Utilities)

**Swift Types:**
- Structs/Enums: PascalCase (`OllamaClient`, `RequestType`, `MemoryType`)
- Protocols: PascalCase, often with suffix (`RequestHandling`, `ErrorTypes`)
- Functions: camelCase (`startSession()`, `addConversationTurn()`)
- Properties: camelCase (`isRunning`, `socketPath`, `enableMemory`)

**Identifiers in Code:**
- Constants: camelCase or ALL_CAPS for module-level (`socketPath: String`, `maxCacheSize = 500`)
- Variables: camelCase (`sessionId`, `ollamaClient`, `requestHandler`)
- Method parameters: camelCase (`request`, `context`, `workingDirectory`)

## Where to Add New Code

**New Feature Command:**
1. Create file in `Sources/AIShellCLI/Commands/` named `[FeatureName]Command.swift`
2. Struct should conform to `AsyncParsableCommand`
3. Add to `AI.subcommands` array in `Sources/AIShellCLI/AI.swift`
4. Use SocketClient to send request, handle Response

**New Request Type:**
1. Add case to `RequestType` enum in `Sources/AIShellCore/Models/Request.swift`
2. Add corresponding fields to `Request.Payload` if needed
3. Add convenience initializer (e.g., `Request.myFeature(...)`)
4. Add handler in `EnhancedRequestHandler.processRequest()` switch statement

**New Phase 2 Component (Memory, RAG, Cache, Prompts):**
1. Create file in `Sources/AIShellCore/[Component]/` directory
2. Implement as `actor` for thread safety if shared state
3. Add initialization in `DaemonService.initializePhase2Components()`
4. Add shutdown in `DaemonService.savePhase2Components()`
5. Wire into `EnhancedRequestHandler` constructor

**New Utility/Helper:**
1. Add to `Sources/AIShellCore/Utilities/` directory or extend `Extensions.swift`
2. Use `LoggerFactory.create(category:)` for logging
3. Make public if needed by other targets

**New External Service Client:**
1. Create in `Sources/AIShellCore/Clients/` (e.g., `MyServiceClient.swift`)
2. Model API response types in companion file (e.g., `MyServiceModels.swift`)
3. Implement as actor for HTTP concurrency
4. Integrate via `DaemonService` or `EnhancedRequestHandler`

**Tests:**
1. Create in `Tests/AIShellTests/` with matching module name
2. Use existing `MockOllamaClient` pattern for test doubles
3. Test files use XCTest framework (standard Swift testing)

## Special Directories

**Sources/AIShellCore/Server/:**
- Purpose: Socket communication layer
- Generated: No
- Committed: Yes
- Critical: Handles all client-daemon IPC

**~/.config/ai-shell/:**
- Purpose: Runtime data and configuration
- Generated: Yes (created at daemon startup if missing)
- Committed: No (user-specific data)
- Contains: config.json (configuration), memory.json (sessions), embeddings.json (RAG), cache.json (response cache), daemon.pid (process ID)

**.build/:**
- Purpose: Swift Package build artifacts
- Generated: Yes (created by `swift build`)
- Committed: No (in .gitignore)

**Tests/AIShellTests/:**
- Purpose: Unit test implementations
- Generated: No
- Committed: Yes
- Included in `swift build` and test runs

## File Organization Principles

**By Layer:**
- CLI layer stays in `AIShellCLI/` (user interaction)
- Core business logic in `AIShellCore/` (reusable, testable)
- Daemon lifecycle in `AIShellDaemon/` (process management)

**By Concern:**
- Communication concerns (Server, Clients) grouped separately
- Feature concerns (Memory, RAG, Cache) in own directories
- Cross-cutting (Utilities) in Utilities directory

**By Lifecycle:**
- Long-lived components (stores) are actors
- Short-lived components (handlers) are structs
- Command structs are transient

## Import Organization Pattern

**Standard Import Order:**
1. Foundation (system frameworks)
2. Concurrency/async imports (Darwin, Glibc)
3. External packages (AsyncHTTPClient, Logging, ArgumentParser, Crypto)
4. Internal modules (AIShellCore)
5. Local relative imports (none - single-file modules only import public APIs)

**Example from SocketServer.swift:**
```swift
import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
```

---

*Structure analysis: 2026-01-23*

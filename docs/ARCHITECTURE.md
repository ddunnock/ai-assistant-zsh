# Architecture Documentation

## System Overview

AI Shell Assistant is a client-server architecture that provides AI-powered command-line assistance using local LLM models. The system consists of three main components:

1. **ZSH Client Plugin** - Shell integration and user interface
2. **Swift Daemon** - Backend service for request routing and LLM communication
3. **Ollama Service** - Local LLM model serving

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                          User's Terminal                        │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │              ZSH Shell with AI Plugin                     │  │
│  │                                                            │  │
│  │  - Command line editing (ZLE)                             │  │
│  │  - Keybinding handlers                                    │  │
│  │  - User functions (ait, aix, aih)                         │  │
│  │  - Socket client (nc)                                     │  │
│  └────────────────┬───────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────┘
                   │
                   │ Unix Domain Socket
                   │ /tmp/ai-shell.sock
                   │ (Length-Prefixed JSON Messages)
                   │
                   ▼
┌─────────────────────────────────────────────────────────────────┐
│                    AI Shell Daemon (Swift)                      │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │                    DaemonService (Actor)                  │  │
│  │                                                            │  │
│  │  - Lifecycle management                                   │  │
│  │  - Signal handling (SIGINT, SIGTERM)                      │  │
│  │  - Component coordination                                 │  │
│  └────────────────┬──────────────────┬────────────────────────┘  │
│                   │                  │                           │
│  ┌────────────────▼─────────┐  ┌────▼──────────────────────┐   │
│  │   SocketServer (Actor)   │  │  RequestHandler (Actor)    │   │
│  │                          │  │                            │   │
│  │  - NWListener            │  │  - Request routing         │   │
│  │  - Connection pool       │  │  - Prompt engineering      │   │
│  │  - Message framing       │  │  - Response formatting     │   │
│  │  - Protocol handling     │  │  - Context aggregation     │   │
│  └──────────────────────────┘  └────────┬───────────────────┘   │
│                                          │                       │
│                                ┌─────────▼────────────────────┐ │
│                                │   OllamaClient (Actor)       │ │
│                                │                              │ │
│                                │  - HTTP client               │ │
│                                │  - Generate/Chat/List APIs   │ │
│                                │  - Health checks             │ │
│                                │  - Timeout handling          │ │
│                                └──────────┬───────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
                                            │
                                            │ HTTP (REST API)
                                            │ localhost:11434
                                            │
                                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                      Ollama Service                             │
│                                                                 │
│  - Model serving (llama3.1, codellama, mistral, etc.)          │
│  - Token generation                                             │
│  - Model management                                             │
└─────────────────────────────────────────────────────────────────┘
```

## Component Details

### 1. ZSH Client Plugin

**Location:** `zsh/ai-assistant.zsh`

**Responsibilities:**
- Provide user-facing shell functions
- Handle keyboard shortcuts via ZLE (ZSH Line Editor)
- Communicate with daemon via Unix socket
- Format and display responses

**Key Functions:**
- `ai_shell_task` - Natural language to commands
- `ai_shell_explain` - Command explanations
- `ai_shell_health` - Health check
- `_ai_shell_send_request` - Socket communication
- `_ai_shell_create_request` - Request payload builder

**Dependencies:**
- `jq` - JSON parsing
- `nc` (netcat) - Unix socket client
- ZSH with ZLE support

### 2. Swift Daemon

#### 2.1 DaemonService

**Location:** `Sources/AIShellDaemon/DaemonService.swift`

**Responsibilities:**
- Application lifecycle management
- Component initialization and coordination
- Signal handling for graceful shutdown
- Health check orchestration

**Concurrency Model:** Actor (thread-safe state management)

#### 2.2 SocketServer

**Location:** `Sources/AIShellCore/Server/SocketServer.swift`

**Responsibilities:**
- Listen on Unix domain socket
- Accept client connections
- Manage connection lifecycle
- Frame/deframe messages (length-prefix protocol)
- Route messages to RequestHandler

**Concurrency Model:** Actor with NWListener

**Protocol:** Length-prefixed JSON
```
┌─────────────┬──────────────────┐
│  4 bytes    │  Variable Length │
│  Length     │  JSON Payload    │
│  (big-end)  │                  │
└─────────────┴──────────────────┘
```

#### 2.3 RequestHandler

**Location:** `Sources/AIShellCore/Server/RequestHandler.swift`

**Responsibilities:**
- Route requests by type (suggest, explain, task, health)
- Build AI prompts from requests
- Aggregate context (history, git, environment)
- Call OllamaClient
- Format responses

**Request Types:**
1. **suggest** - Command completion/improvement
   - Uses command history and git context
   - Short, concise prompts

2. **explain** - Command explanation
   - Detailed breakdown of command parts
   - Risk/side-effect analysis

3. **task** - Natural language to shell commands
   - Task description to executable commands
   - Working directory context

4. **health** - Service health check
   - Verifies Ollama connectivity
   - No LLM call required

#### 2.4 OllamaClient

**Location:** `Sources/AIShellCore/Clients/OllamaClient.swift`

**Responsibilities:**
- HTTP communication with Ollama
- API endpoint management
- Timeout and error handling
- Response parsing

**Endpoints Used:**
- `POST /api/generate` - Text generation
- `POST /api/chat` - Multi-turn chat
- `GET /api/tags` - List models (health check)

**Concurrency Model:** Actor with AsyncHTTPClient

### 3. Ollama Service

**External Dependency:** [Ollama](https://ollama.com)

**Responsibilities:**
- Load and serve LLM models
- Token generation and sampling
- Model management (pull, list, delete)
- GPU/CPU optimization

**API:** REST API on http://localhost:11434

## Data Flow

### Suggest Request Flow

```
1. User types: "git co" + Ctrl+Space

2. ZSH Plugin
   └─> _ai_shell_zle_suggest()
       └─> ai_shell_suggest("git co")
           └─> _ai_shell_create_request("suggest", "git co")
               └─> Builds JSON with history, git branch, env
           └─> _ai_shell_send_request(json)
               └─> nc -U /tmp/ai-shell.sock
                   └─> Sends: [4-byte length][JSON payload]

3. Daemon: SocketServer
   └─> Receives bytes on NWConnection
   └─> Deframes message (reads length, then payload)
   └─> Decodes JSON to Request struct
   └─> Passes to RequestHandler

4. Daemon: RequestHandler
   └─> handle(request)
       └─> Switches on request.type: .suggest
       └─> handleSuggest(request)
           └─> buildSuggestPrompt(command, context)
               └─> Includes: command, history (last 5), git branch
           └─> ollamaClient.generate(prompt, system)

5. Daemon: OllamaClient
   └─> generate(prompt, system)
       └─> POST /api/generate
           └─> Request: { model, prompt, system, stream: false }
       └─> Waits for Ollama response
       └─> Returns: completion text

6. Daemon: RequestHandler
   └─> Creates Response.success(suggestion: "git checkout main")
   └─> Returns to SocketServer

7. Daemon: SocketServer
   └─> Encodes Response to JSON
   └─> Frames message (adds length prefix)
   └─> Sends to client connection

8. ZSH Plugin
   └─> Receives response from nc
   └─> Strips length prefix
   └─> Parses JSON with jq
   └─> Extracts .payload.suggestion
   └─> Updates BUFFER to "git checkout main"
   └─> Moves cursor to end of line

9. User sees: "git checkout main" in terminal
```

## Message Protocol

### Request Format

```json
{
  "id": "req-1234567890-999",
  "type": "suggest|explain|task|health",
  "payload": {
    "command": "git co",           // For suggest/explain
    "task": "find python files",   // For task
    "workingDirectory": "~/project",
    "context": {
      "history": ["ls", "cd src", "git status"],
      "gitBranch": "main",
      "environment": {
        "SHELL": "/bin/zsh",
        "USER": "username"
      }
    }
  },
  "timestamp": "2025-11-17T12:34:56Z"
}
```

### Response Format

```json
{
  "id": "resp-1234567890-999",
  "requestId": "req-1234567890-999",
  "status": "success|error|partial",
  "payload": {
    "suggestion": "git checkout main",    // For suggest
    "explanation": "This command...",    // For explain
    "commands": ["find . -name '*.py'"], // For task
    "error": {                           // For error
      "code": "ERROR_CODE",
      "message": "Error description"
    }
  },
  "timestamp": "2025-11-17T12:34:57Z",
  "processingTime": 1.234
}
```

## Concurrency Model

### Actor-Based Architecture

All daemon components use Swift's actor model for thread-safe concurrency:

```swift
// Each component is an actor
actor DaemonService { /* ... */ }
actor SocketServer { /* ... */ }
actor RequestHandler { /* ... */ }
actor OllamaClient { /* ... */ }

// Actors ensure:
// - Isolated state (no data races)
// - Sequential access to mutable state
// - Async/await for communication
```

### Request Processing Concurrency

```
Multiple Client Connections (Concurrent)
    │
    ├─> Connection 1 ─┐
    ├─> Connection 2 ─┤
    ├─> Connection 3 ─┤─> SocketServer (Actor)
    └─> Connection N ─┘         │
                                │ Serialized per connection
                                ▼
                        RequestHandler (Actor)
                                │
                                │ Serialized requests
                                ▼
                        OllamaClient (Actor)
                                │
                                │ HTTP requests
                                ▼
                        Ollama Service (Thread Pool)
```

## Error Handling

### Error Types

```swift
enum AIShellError: Error {
    case requestError(String)       // Invalid request
    case ollamaError(String)        // Ollama API error
    case networkError(String)       // Network/socket error
    case configurationError(String) // Config parsing error
    case timeoutError(String)       // Request timeout
}
```

### Error Flow

```
Error Occurs
    │
    ├─> Caught in component (OllamaClient, etc.)
    │   └─> Logged with context
    │   └─> Throws to RequestHandler
    │
    ├─> RequestHandler catches
    │   └─> Logs error
    │   └─> Creates error Response
    │   └─> Returns to SocketServer
    │
    ├─> SocketServer
    │   └─> Sends error response to client
    │
    └─> ZSH Plugin
        └─> Parses error response
        └─> Shows user-friendly message
```

## Performance Considerations

### Optimizations

1. **Connection Pooling**
   - OllamaClient reuses HTTPClient
   - Reduces connection overhead

2. **Async/Await**
   - Non-blocking I/O throughout
   - Concurrent request handling

3. **Efficient Framing**
   - Length-prefixed protocol
   - No delimiter scanning required

4. **Actor Isolation**
   - No locks needed
   - Eliminates contention

### Bottlenecks

1. **LLM Generation**
   - Main latency source (1-5s typically)
   - Depends on model size and hardware

2. **JSON Parsing**
   - Negligible with Swift Codable
   - < 1ms per request

3. **Socket Communication**
   - Local Unix socket: < 1ms
   - Negligible overhead

## Security

### Threat Model

**In Scope:**
- Local privilege escalation via socket
- Malicious AI-generated commands
- Sensitive data in logs

**Out of Scope:**
- Network attacks (local-only)
- Model poisoning (user controls Ollama)

### Mitigations

1. **Socket Permissions**
   ```swift
   // Socket created with 0o600 (owner read/write only)
   let permissions: NWParameters.SocketPermissions = .ownerReadWrite
   ```

2. **No Auto-Execution**
   - User must explicitly execute suggested commands
   - Confirmation required for task execution

3. **Sanitized Logging**
   - Sensitive env vars filtered
   - No password/token logging

4. **Local-Only**
   - No external network calls
   - All data stays on device

## Future Enhancements

### Planned

1. **Streaming Responses**
   - Use Ollama's streaming API
   - Progressive display in terminal

2. **Response Caching**
   - Cache frequent explanations
   - Reduce Ollama load

3. **Context Persistence**
   - Save conversation history
   - Multi-turn interactions

4. **Command Safety Checks**
   - Detect dangerous patterns
   - Warn before execution

### Under Consideration

1. **Multi-Model Support**
   - Auto-select model per task type
   - Fallback chains

2. **Plugin System**
   - Custom request handlers
   - Extensible prompts

3. **Web Dashboard**
   - Real-time monitoring
   - Usage analytics

4. **Bash/Fish Support**
   - Shell-agnostic client protocol
   - Multiple client implementations

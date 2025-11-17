# Phase 2 Features Guide

This guide covers the advanced Phase 2 features of AI Shell Assistant: Memory, RAG (Retrieval-Augmented Generation), Caching, and Streaming.

## Overview

Phase 2 transforms AI Shell Assistant from a stateless command helper into an intelligent, context-aware system that:
- **Remembers** your preferences and past interactions
- **Learns** from documentation you provide
- **Responds faster** by caching common queries
- **Provides better suggestions** using relevant context

## Table of Contents

1. [Memory System](#memory-system)
2. [RAG (Document Indexing & Search)](#rag-document-indexing--search)
3. [Response Caching](#response-caching)
4. [Configurable Prompts](#configurable-prompts)
5. [Streaming Responses](#streaming-responses)
6. [Configuration](#configuration)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

---

## Memory System

The memory system gives the AI assistant a persistent memory across sessions.

### Types of Memory

1. **Session Memory**: Conversation history within the current session
2. **Long-term Memory**: Facts and preferences that persist across restarts
3. **Command Memory**: Tracks command execution with success/failure patterns
4. **Project Memory**: Context specific to your project directories

### Commands

#### `ai_shell_remember` (alias: `air`)

Store facts in long-term memory.

```bash
# Remember preferences
air I prefer verbose git commit messages
air Use docker-compose for local development
air The staging server is staging.example.com

# Remember project-specific info
cd ~/my-project
air This project uses Python 3.11
air Run tests with: pytest tests/ -v
```

**How it works:**
- Facts are stored with importance scoring (0.0 to 1.0)
- Higher importance facts are retained longer
- Facts are tied to timestamps for recency sorting
- Metadata can include tags for organization

#### `ai_shell_recall` (alias: `airc`)

Query memory for relevant information.

```bash
# Recall preferences
airc git preferences
# Output:
# Memories matching 'git preferences':
# ---
# [longTerm] I prefer verbose git commit messages
# [longTerm] Always create feature branches from main

# Recall project info
airc python version
# Output:
# [project] This project uses Python 3.11
# [command] python --version (successful)
```

**Search features:**
- Keyword matching across all memory types
- Returns up to 5 most relevant memories
- Shows memory type in brackets `[type]`
- Sorted by relevance and recency

### Automatic Memory

The system automatically remembers:
- Conversation history (last 50 turns per session)
- Command execution results (success/failure)
- Working directories and git branches
- Project-specific context

### Memory Storage

Memory is stored in `~/.config/ai-shell/memory.json`

**File structure:**
```json
{
  "memories": {
    "longTerm": [...],
    "command": [...],
    "project": [...]
  },
  "sessions": {
    "session-id": {
      "conversationHistory": [...],
      "lastActivity": "2025-11-17T...",
      ...
    }
  }
}
```

### Memory Management

**Automatic pruning:**
- Old, low-importance memories are removed when limit is reached
- Scoring: `importance * 0.7 + recency * 0.3`
- Default limit: 1000 memories per type

**Manual management:**
```bash
# View memory file
cat ~/.config/ai-shell/memory.json | jq .

# Clear all memory (nuclear option)
rm ~/.config/ai-shell/memory.json
# Restart daemon to start fresh
```

---

## RAG (Document Indexing & Search)

RAG enables the AI to provide context-aware responses using your documentation.

### What is RAG?

Retrieval-Augmented Generation means:
1. **Index** your documentation as vector embeddings
2. **Search** semantically (by meaning, not just keywords)
3. **Augment** AI prompts with relevant context
4. **Generate** better, more informed responses

### Commands

#### `ai_shell_index` (alias: `aii`)

Index documentation files for semantic search.

```bash
# Index a single file
aii README.md

# Index multiple files
aii docs/api.md docs/deployment.md

# Index with glob patterns
aii docs/**/*.md
aii *.md

# Index from another directory
cd ~/my-project
aii README.md CONTRIBUTING.md

# Output:
# Indexing README.md ... ✓
# Indexing CONTRIBUTING.md ... ✓
#
# Indexed: 2 files
```

**What gets indexed:**
- Markdown files (.md)
- README files
- Man pages
- Help text output
- Code comments (future)

**Indexing process:**
1. File content is read
2. Text is converted to vector embedding using Ollama
3. Embedding stored with metadata (title, source, working directory)
4. Original text saved for retrieval

#### `ai_shell_search` (alias: `ais`)

Semantic search across indexed documents.

```bash
# Search for deployment info
ais deployment process

# Output:
# Searching for: deployment process
#
# Results:
# ---
# [0.92] docs/deployment.md: To deploy the application, first build the Docker image...
# [0.85] README.md: Deployment is handled via CI/CD pipeline...
# [0.78] docs/api.md: The API deployment requires environment variables...

# Search project-specific docs
cd ~/my-project
ais how to run tests

# Search for error solutions
ais fix database connection error
```

**Search features:**
- Semantic matching (understands meaning, not just keywords)
- Cosine similarity scoring (0.0 to 1.0)
- Project-aware (searches current directory first)
- Returns top 5 matches with similarity scores
- Shows preview of matched content

### Automatic RAG Integration

When RAG is enabled, the system automatically:

**For `suggest` requests:**
- Searches for relevant command examples
- Injects top 2 matches into prompt
- Provides context-aware suggestions

**For `explain` requests:**
- Searches for man pages and documentation
- Includes relevant docs in explanation
- More accurate, detailed explanations

**For `task` requests:**
- Searches for similar task examples
- Includes relevant procedures
- Better command generation from natural language

### Storage

Embeddings stored in `~/.config/ai-shell/embeddings.json`

**File structure:**
```json
[
  {
    "id": "uuid",
    "content": "Full text content...",
    "embedding": [0.123, 0.456, ...],  // Vector (typically 384-4096 dimensions)
    "metadata": {
      "source": "readme",
      "title": "README.md",
      "workingDirectory": "~/my-project",
      "importance": 0.9
    },
    "timestamp": "2025-11-17T..."
  },
  ...
]
```

### RAG Best Practices

**What to index:**
✅ Project READMEs
✅ API documentation
✅ Deployment guides
✅ Architecture docs
✅ Runbooks and procedures

**What NOT to index:**
❌ Code files (too granular, poor for RAG)
❌ Log files (noisy, not useful)
❌ Binary files
❌ Generated files

**Optimal indexing strategy:**
```bash
# Index project documentation
cd ~/my-project
aii README.md
aii docs/**/*.md

# Index global references
cd ~/.config/ai-shell
aii docker-cheatsheet.md
aii kubernetes-commands.md
```

---

## Response Caching

Caching eliminates redundant LLM calls for improved performance.

### How It Works

1. **Before LLM call**: Check if we've seen this request before
2. **Cache hit**: Return cached response instantly (< 1ms)
3. **Cache miss**: Call LLM, cache the response
4. **Next time**: Cache hit! Much faster

### What Gets Cached

- Command explanations (`ai_shell_explain`)
- Command suggestions (`ai_shell_suggest`)
- Common task conversions

**Cache key generation:**
```
SHA256(request_type + content + relevant_context)
```

### Cache Statistics

Check cache effectiveness:
```bash
aih  # ai_shell_health
```

Output includes:
```
✓ AI Shell Assistant daemon is healthy
  Socket: /tmp/ai-shell.sock
  cache: enabled
  cache_entries: 47
  cache_hits: 156
```

### Cache Management

**Automatic management:**
- LRU-style eviction (least recently used)
- Scoring: `hit_count * 0.6 + recency * 0.4`
- Max size: 500 entries (configurable)
- Max age: 7 days (configurable)

**Manual management:**
```bash
# View cache
cat ~/.config/ai-shell/cache.json | jq .

# Clear cache
rm ~/.config/ai-shell/cache.json
# Restart daemon
```

### Performance Impact

**Without cache:**
- Explain command: ~2-5 seconds
- Suggest command: ~1-3 seconds

**With cache (hit):**
- Any command: < 10ms
- 100-500x faster!

---

## Configurable Prompts

Customize how the AI responds without changing code.

### Prompt Templates

Templates use Handlebars-style syntax:
- Variables: `{{variable}}`
- Conditionals: `{{#if condition}}...{{/if}}`
- Iteration: `{{#each array}}...{{/each}}`

### Default Templates

Located in `~/.config/ai-shell/prompts.json`

**Suggest template:**
```
Current command: {{command}}
{{#if gitBranch}}
Git branch: {{gitBranch}}
{{/if}}
{{#if relevantContext}}
Relevant examples:
{{relevantContext}}
{{/if}}

Suggest an improvement or completion for the current command.
```

### Customizing Prompts

1. **Copy defaults** (optional):
```bash
# Daemon creates prompts.json on first run with defaults
cat ~/.config/ai-shell/prompts.json
```

2. **Edit templates**:
```bash
vim ~/.config/ai-shell/prompts.json
```

3. **Restart daemon**:
```bash
killall ai-shell-daemon
ai-shell-daemon --config ~/.config/ai-shell/config.json &
```

### Example Customizations

**More concise suggestions:**
```json
{
  "suggest_system": {
    "system": "You are a shell expert. Suggest command completions. Output ONLY the command, no explanations.",
    "user": null
  },
  "suggest_user": {
    "system": null,
    "user": "Complete: {{command}}"
  }
}
```

**Include more history:**
```json
{
  "suggest_user": {
    "system": null,
    "user": "Current command: {{command}}\n\n{{#if history}}Last 10 commands:\n{{#each history}}{{this}}\n{{/each}}{{/if}}\n\nSuggest completion."
  }
}
```

---

## Streaming Responses

Stream LLM responses token-by-token for better UX.

### Status

**Current:** Disabled by default (Phase 2 infrastructure complete)
**Future:** Will enable progressive output display

### Enabling (Experimental)

In `config.json`:
```json
{
  "enableStreaming": true
}
```

**Note:** ZSH plugin doesn't yet display streaming output progressively. This will be added in a future update.

### How It Works

When enabled:
1. Request sent to Ollama with `stream: true`
2. Response arrives as newline-delimited JSON chunks
3. Each chunk processed immediately
4. Callback invoked with each token
5. Full response assembled progressively

---

## Configuration

### Complete Configuration Example

`~/.config/ai-shell/config.json`:
```json
{
  "socketPath": "/tmp/ai-shell.sock",
  "ollamaURL": "http://localhost:11434",
  "model": "llama3.1:8b",
  "logLevel": "info",

  "_comment_phase2": "Phase 2 features",
  "enableMemory": true,
  "enableRAG": true,
  "enableCache": true,
  "enableStreaming": false,

  "_comment_storage": "Custom storage paths (optional)",
  "memoryStoragePath": null,
  "ragStoragePath": null,
  "cacheStoragePath": null,
  "promptsStoragePath": null,

  "_comment_tuning": "Performance tuning",
  "maxMemoryAge": 24,
  "maxCacheAge": 7,
  "ragMinSimilarity": 0.6
}
```

### Configuration Options

| Option | Default | Description |
|--------|---------|-------------|
| `enableMemory` | `true` | Enable memory system |
| `enableRAG` | `true` | Enable document indexing/search |
| `enableCache` | `true` | Enable response caching |
| `enableStreaming` | `false` | Enable streaming responses |
| `maxMemoryAge` | `24` | Hours to keep session memory |
| `maxCacheAge` | `7` | Days to keep cached responses |
| `ragMinSimilarity` | `0.6` | Minimum similarity for RAG matches (0.0-1.0) |

### Storage Paths

By default, all data stored in `~/.config/ai-shell/`:
- `memory.json` - Memory database
- `embeddings.json` - RAG vectors
- `cache.json` - Response cache
- `prompts.json` - Custom prompt templates

Override with custom paths:
```json
{
  "memoryStoragePath": "/custom/path/memory.json",
  "ragStoragePath": "/custom/path/embeddings.json"
}
```

---

## Best Practices

### Memory

1. **Be specific when remembering:**
   ```bash
   # Good
   air For this project, run tests with: npm test --coverage

   # Less useful
   air I like npm
   ```

2. **Remember project context:**
   ```bash
   cd ~/important-project
   air This is a critical production service
   air Deploy only during maintenance windows
   ```

3. **Recall before asking:**
   ```bash
   airc deployment
   # Check what you've already stored before asking AI
   ```

### RAG

1. **Index strategically:**
   ```bash
   # Index when starting a new project
   cd ~/new-project
   aii README.md docs/*.md

   # Re-index when docs change
   aii docs/updated-guide.md
   ```

2. **Search before tasking:**
   ```bash
   # Check docs first
   ais how to deploy

   # Then use task with context
   ait deploy to staging
   ```

3. **Keep docs updated:**
   - Index fresh documentation
   - Remove outdated content
   - Higher quality docs = better AI responses

### Performance

1. **Use cache-friendly queries:**
   ```bash
   # These will be cached
   aix "docker ps"
   aix "docker ps"  # Cache hit! Instant response
   ```

2. **Enable all Phase 2 features:**
   - Memory provides context
   - RAG provides examples
   - Cache provides speed
   - Together they're powerful!

---

## Troubleshooting

### Memory Issues

**Problem:** Memory not persisting

**Solution:**
```bash
# Check memory file exists
ls -la ~/.config/ai-shell/memory.json

# Check permissions
chmod 644 ~/.config/ai-shell/memory.json

# Verify memory is enabled
grep enableMemory ~/.config/ai-shell/config.json
```

**Problem:** Memory growing too large

**Solution:**
```bash
# Reduce retention
# In config.json:
{
  "maxMemoryAge": 12  # Shorter retention
}

# Or clear old memories
rm ~/.config/ai-shell/memory.json
```

### RAG Issues

**Problem:** Search returns no results

**Causes:**
- Nothing indexed yet
- Similarity threshold too high
- Query too specific

**Solutions:**
```bash
# Check what's indexed
cat ~/.config/ai-shell/embeddings.json | jq '. | length'

# Index some docs
aii README.md

# Lower similarity threshold in config
{
  "ragMinSimilarity": 0.4  # More lenient
}
```

**Problem:** Indexing fails

**Solution:**
```bash
# Check Ollama is running
curl http://localhost:11434/api/tags

# Check model supports embeddings
ollama list | grep llama3.1

# Restart daemon
killall ai-shell-daemon
ai-shell-daemon &
```

### Cache Issues

**Problem:** Cache not speeding things up

**Solution:**
```bash
# Check cache is enabled
aih | grep cache

# Check cache has entries
cat ~/.config/ai-shell/cache.json | jq '. | length'

# Verify you're making repeated queries
aix "ls"  # First time: slow
aix "ls"  # Second time: should be fast
```

**Problem:** Stale cache responses

**Solution:**
```bash
# Clear cache
rm ~/.config/ai-shell/cache.json

# Or reduce cache TTL in config
{
  "maxCacheAge": 1  # 1 day instead of 7
}
```

### General Phase 2 Issues

**All features disabled:**
```bash
# Check health
aih

# Should show:
# memory: enabled
# rag: enabled
# cache: enabled

# If not, check config
cat ~/.config/ai-shell/config.json | grep enable
```

**Daemon crashes with Phase 2:**
```bash
# Check logs
cat ~/.config/ai-shell/daemon.error.log

# Run in verbose mode
ai-shell-daemon --verbose

# Common issues:
# - Corrupted JSON files (delete and restart)
# - Ollama not running (start Ollama)
# - Permissions issues (check ~/.config/ai-shell/)
```

---

## Advanced Usage

### Combining Features

**Example: Smart project assistant**
```bash
# 1. Index project documentation
cd ~/my-project
aii README.md docs/**/*.md

# 2. Remember project specifics
air This project uses Kubernetes for deployment
air Run migrations with: kubectl exec -it pod -- migrate

# 3. Use context-aware commands
ait deploy the API to staging
# AI now has:
# - Project docs (RAG)
# - Deployment facts (memory)
# - Past deployments (memory + cache)
```

### Memory + RAG Workflow

```bash
# New project setup
cd ~/awesome-app
aii *.md
air Primary developer: alice@example.com
air Database: PostgreSQL 14

# Daily usage
ait how do I run the tests
# Uses: README.md (RAG) + past conversations (memory)

airc database
# Shows: PostgreSQL 14, connection details, past DB commands

ais authentication
# Finds: Auth docs, API endpoints, examples
```

---

## See Also

- [Configuration Guide](CONFIGURATION.md) - Detailed configuration options
- [Architecture](ARCHITECTURE.md) - How Phase 2 works internally
- [Main README](../README.md) - Project overview and quick start

---

**Phase 2 transforms AI Shell Assistant from a simple helper into an intelligent, context-aware partner that learns and improves over time!**

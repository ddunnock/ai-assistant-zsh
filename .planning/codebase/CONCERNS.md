# Codebase Concerns

**Analysis Date:** 2026-01-23

## Tech Debt

**Incomplete Phase 2 Feature Implementation:**
- Issue: `handleForget()` in `Sources/AIShellCore/Server/EnhancedRequestHandler.swift` (line 504-511) returns success without actually implementing selective memory deletion. Function logs "not yet implemented" but doesn't throw an error.
- Files: `Sources/AIShellCore/Server/EnhancedRequestHandler.swift`
- Impact: Users can call the forget endpoint but memory is never actually deleted, leading to false expectations and data accumulation.
- Fix approach: Either implement full deletion logic with index management, or return a not-implemented error to guide users toward actual implementations.

**Unsafe Pointer Arithmetic in Socket Operations:**
- Issue: Direct pointer arithmetic using `baseAddress!` without bounds checking in socket read/write operations.
- Files:
  - `Sources/AIShellCore/Server/SocketServer.swift` (lines 242, 268)
- Impact: Potential buffer overrun if the calculation `totalRead` or `totalWritten` exceeds buffer bounds. Force-unwrapping baseAddress could panic if pointer is nil.
- Fix approach: Use Swift's safe buffer access APIs or validate offset calculations before pointer arithmetic. Replace `baseAddress! + offset` with proper bounds checking.

**Unsound Sendable Conformance:**
- Issue: `Connection` class in `Sources/AIShellCore/Server/SocketServer.swift` (line 182) uses `@unchecked Sendable` despite containing mutable state (`isActive`, socket file descriptor).
- Files: `Sources/AIShellCore/Server/SocketServer.swift` (line 182)
- Impact: Potential data races if Connection state is accessed from multiple async contexts. The @unchecked annotation suppresses compiler safety checks.
- Fix approach: Implement proper thread-safe synchronization or refactor to use isolated(any) protocols consistently.

**Cache Key Collision Risk:**
- Issue: Cache key generation in `Sources/AIShellCore/Cache/ResponseCache.swift` (lines 101-117) uses a simple string concatenation with pipe separators before hashing. Content itself is included in the key, which could create collisions if content contains pipe characters.
- Files: `Sources/AIShellCore/Cache/ResponseCache.swift` (lines 101-117)
- Impact: Different queries could hash to the same cache key, returning incorrect cached results.
- Fix approach: Use proper serialization (JSON or length-prefixed) before hashing to prevent collision vectors.

## Known Bugs

**Streaming Chunk Decode Errors Silently Ignored:**
- Symptoms: When Ollama streaming returns malformed JSON chunks, errors are logged but processing continues. This could result in incomplete or incorrect responses being returned to users without obvious indication of data corruption.
- Files: `Sources/AIShellCore/Clients/OllamaClient.swift` (lines 303-312)
- Trigger: Ollama service returns invalid JSON in stream chunks, network corruption, or protocol version mismatch.
- Workaround: Check logs for decode errors. Stream chunks are skipped but processing continues.
- Fix approach: Track decode error count and fail the entire streaming operation if corruption rate exceeds threshold, or return partial result with error indicator.

**Socket Path Length Not Validated Early:**
- Symptoms: If socket path exceeds UNIX_PATH_MAX (typically 104 bytes on macOS), the bind fails but the socket file descriptor is closed properly, returning appropriate error.
- Files: `Sources/AIShellCore/Server/SocketServer.swift` (lines 60-63)
- Trigger: Configure socket path longer than 104 characters on macOS.
- Workaround: Ensure socket path is kept under ~100 characters when configuring daemon.
- Fix approach: Validate path length earlier and provide clear guidance on maximum allowed length.

## Security Considerations

**Unvalidated File Operations:**
- Risk: Multiple calls to `try? FileManager.default.removeItem()` silently ignore errors in cleanup operations. An attacker could race condition these operations or symlink attacks could occur.
- Files:
  - `Sources/AIShellCore/Server/SocketServer.swift` (lines 36, 85, 125)
  - `Sources/AIShellDaemon/DaemonService.swift` (line 291)
  - `Sources/AIShellCLI/DaemonManager.swift` (lines 114, 141, 196, 204)
- Current mitigation: Socket file created with restrictive 0o600 permissions (line 90). Pid/socket files in /tmp.
- Recommendations:
  - Use `FileManager.removeItem()` without try? and handle errors explicitly to detect attacks
  - Verify file ownership before deletion
  - Use secure temporary directories (not /tmp if possible)
  - Implement atomic operations or use exclusive locks

**Command Safety Checker Pattern Gaps:**
- Risk: Regex patterns in `CommandSafetyChecker` may not catch all dangerous patterns. For example, obfuscated commands using hex escapes or base64 encoding could bypass detection.
- Files: `Sources/AIShellCore/Utilities/CommandSafetyChecker.swift` (lines 65-120)
- Current mitigation: Multiple patterns covering common dangerous operations. Only provides warnings, not blocking.
- Recommendations:
  - Add support for detecting obfuscated commands (hex, base64, unicode escapes)
  - Consider adding YARA rules or bytecode analysis
  - Document which patterns are NOT covered
  - Make safety warnings actionable (blocking vs. warning levels)

**Input Validation Insufficient for LLM Context:**
- Risk: `InputValidator` checks length and basic null bytes, but doesn't validate against prompt injection attacks. Crafted input could manipulate LLM system prompts.
- Files: `Sources/AIShellCore/Utilities/InputValidator.swift`
- Current mitigation: Length limits and null byte checks.
- Recommendations:
  - Add prompt injection detection (detect nested quotes, system prompt keywords)
  - Sanitize variables before template rendering
  - Use structured prompting techniques instead of string interpolation

**Nil Response IDs in Error Handling:**
- Risk: In `Sources/AIShellCore/Server/SocketServer.swift` (line 326), when processing fails completely, a new UUID is generated for error response instead of using the original request ID. Client cannot correlate errors to requests.
- Files: `Sources/AIShellCore/Server/SocketServer.swift` (lines 325-329)
- Current mitigation: None. Error response uses random UUID.
- Recommendations: Parse the request ID before full JSON parsing, or use a try-parse approach to extract at least the ID.

## Performance Bottlenecks

**Embedding Generation for Every Search:**
- Problem: Every search query in `EmbeddingStore.search()` requires generating an embedding by calling Ollama API, even for identical queries.
- Files: `Sources/AIShellCore/RAG/EmbeddingStore.swift` (line 134)
- Cause: No caching of query embeddings. Each identical query triggers a full embedding generation.
- Improvement path:
  - Implement LRU cache for query embeddings (separate from document cache)
  - Consider batch embedding for multiple queries
  - Profile to determine cache size needed

**Memory Pruning Happens During Add:**
- Problem: When documents/memories exceed limit, entire dataset is sorted during `addDocument()` or `addMemory()`. This is O(n log n) blocking operation in hot path.
- Files:
  - `Sources/AIShellCore/RAG/EmbeddingStore.swift` (lines 105-118)
  - `Sources/AIShellCore/Memory/MemoryStore.swift` (lines 203-217)
- Cause: Pruning logic not optimized for frequency of add operations.
- Improvement path:
  - Use priority queue or heap to maintain top-k items incrementally
  - Batch pruning into background task
  - Profile actual pruning frequency to justify optimization cost

**Full Cache Rescan for Statistics:**
- Problem: `ResponseCache.getStatistics()` iterates entire cache to compute age distribution on every call.
- Files: `Sources/AIShellCore/Cache/ResponseCache.swift` (lines 132-163)
- Cause: Statistics computed on-demand without incremental updates.
- Improvement path: Maintain running age distribution counters, update incrementally as entries are added/removed.

**String Interpolation in Prompts:**
- Problem: Prompts are built using string interpolation with potentially large context (command history, file content). No lazy evaluation or streaming.
- Files:
  - `Sources/AIShellCore/Server/RequestHandler.swift` (lines 91-102, 120-127)
  - `Sources/AIShellCore/Server/EnhancedRequestHandler.swift` (lines 147-171)
- Cause: All context concatenated into single string before sending to LLM.
- Improvement path: Implement streaming prompt construction or use structured prompt formatting to reduce memory footprint for large contexts.

## Fragile Areas

**JSON Decoding with Custom Date Strategy:**
- Files: `Sources/AIShellCore/Server/SocketServer.swift` (lines 290-291)
- Why fragile: Uses custom `DateCoding.flexibleISO8601` strategy that may have edge cases. If strategy parsing fails, entire request fails silently.
- Safe modification:
  - Test date parsing with various formats before production
  - Add logging before/after date parsing to debug issues
  - Consider using RFC3339 with nanosecond precision instead of custom strategy
- Test coverage: Likely limited for date edge cases (leap seconds, different timezones, etc.)

**Actor Isolation and Shared Memory:**
- Files:
  - `Sources/AIShellCore/RAG/EmbeddingStore.swift` (line 79) - documents array
  - `Sources/AIShellCore/Memory/MemoryStore.swift` (lines 97-99) - memories and sessions dicts
  - `Sources/AIShellCore/Cache/ResponseCache.swift` (line 31) - cache dict
- Why fragile: All mutable state stored as simple Swift Collections without bounds checking. If in-memory corruption occurs, no recovery mechanism.
- Safe modification:
  - Add invariant checks after major mutations
  - Implement versioning for in-memory structures
  - Add checksums when persisting to detect corruption on load
- Test coverage: No tests for concurrent access patterns or state corruption recovery.

**Unframed Message Handling:**
- Files: `Sources/AIShellCore/Server/SocketServer.swift` (lines 204-228)
- Why fragile: Protocol assumes strict framing with length prefix, but if client sends malformed frame or partial messages during network issues, Connection.start() loops indefinitely or crashes.
- Safe modification:
  - Add connection timeout
  - Implement message framing with CRC or checksum
  - Add state machine to detect protocol violations
- Test coverage: No tests for malformed/partial frames.

## Scaling Limits

**In-Memory Only Storage:**
- Current capacity: 5,000 documents, 1,000 memories per type, 500 cache entries
- Limit: After exceeding limits, oldest/least-important items are discarded. No persistence across daemon restarts for cache.
- Scaling path:
  - Implement SQLite backend for memories and cache with proper indexing
  - Use vector database (Milvus, Weaviate) for embeddings instead of in-memory array
  - Implement sharding for multi-tenant scenarios
  - Add eviction metrics to understand when limits are hit

**Single Daemon Process:**
- Current capacity: Single daemon handles all requests sequentially (though async)
- Limit: Cannot scale horizontally. Daemon crash loses all in-memory state.
- Scaling path:
  - Implement daemon clustering with shared backend
  - Use message queue (Redis) for request distribution
  - Add persistence layer for fault recovery
  - Implement graceful shutdown with state flush

**HTTP Client Connection Pooling:**
- Current capacity: Single HTTPClient instance shared across all requests
- Limit: May hit connection limits if many concurrent embedding generation requests
- Scaling path:
  - Configure HTTPClient with connection pool size limits
  - Monitor connection usage and add metrics
  - Consider implementing request queuing if limits are hit

## Dependencies at Risk

**OllamaClient HTTP Timeouts:**
- Risk: Ollama service might be slow or unresponsive, causing requests to hang despite timeout configuration
- Impact: User experience degradation, potential cascading failures
- Current mitigation: 30-second read timeout (line 28 in OllamaClient.swift)
- Migration plan:
  - Add circuit breaker pattern for Ollama connectivity
  - Implement fallback to cached responses
  - Add health check monitoring with alerting

**Regex Compilation on Every Check:**
- Risk: `CommandSafetyChecker.check()` compiles regex patterns on every call instead of caching
- Impact: Performance degradation with many safety checks
- Current mitigation: Only called on generated commands
- Migration plan:
  - Compile patterns once at startup
  - Use pre-compiled static patterns
  - Consider using a regex matching library with compilation caching

## Missing Critical Features

**No Audit Logging:**
- Problem: Commands generated by LLM are not logged with user context, making it impossible to audit which commands were suggested or executed
- Blocks: Compliance with security policies, debugging user issues
- Priority: High

**No Request Rate Limiting:**
- Problem: No protection against abuse or resource exhaustion through rapid requests
- Blocks: Multi-user scenarios, preventing DoS attacks
- Priority: High

**No Model Version Management:**
- Problem: No way to track which model was used for each response, making it impossible to reproduce or debug responses
- Blocks: Debugging model-specific issues, A/B testing different models
- Priority: Medium

**No Async Error Recovery:**
- Problem: If Ollama service crashes during request, no automatic reconnection or request retry
- Blocks: Resilience in production deployments
- Priority: High

## Test Coverage Gaps

**Socket Protocol:**
- What's not tested: Malformed JSON, partial messages, connection resets, frame size violations
- Files: `Sources/AIShellCore/Server/SocketServer.swift`
- Risk: Silent failures or protocol corruption could go undetected
- Priority: High

**Concurrent Access:**
- What's not tested: Multiple simultaneous requests to actors, concurrent memory/RAG/cache operations
- Files: `Sources/AIShellCore/Memory/MemoryStore.swift`, `Sources/AIShellCore/RAG/EmbeddingStore.swift`, `Sources/AIShellCore/Cache/ResponseCache.swift`
- Risk: Data corruption or race conditions in multi-request scenarios
- Priority: High

**Persistence and Recovery:**
- What's not tested: Corrupted JSON files, missing storage directories, incomplete writes during daemon crash
- Files: Memory/RAG/Cache save/load operations
- Risk: Data loss or corruption on restart
- Priority: Medium

**Ollama Integration Failures:**
- What's not tested: Network errors, malformed responses, timeout handling, connection pooling
- Files: `Sources/AIShellCore/Clients/OllamaClient.swift`
- Risk: Unhandled API changes or network issues could crash daemon
- Priority: High

---

*Concerns audit: 2026-01-23*

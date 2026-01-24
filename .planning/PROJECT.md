# AIShellAssistant Performance Optimization

**Project Start:** 2026-01-23
**Status:** Active

## Vision

Transform AIShellAssistant from a functional CLI assistant into a responsive, production-ready tool by addressing performance bottlenecks identified in the codebase audit. The goal is sub-second response times for cached/similar queries while maintaining the current feature set.

## Problem Statement

Command suggestions currently experience noticeable latency due to:
1. **Embedding generation on every search** - No query caching means identical queries regenerate embeddings
2. **O(n log n) pruning in hot paths** - Memory/RAG stores sort entire datasets during add operations
3. **Full cache rescan for statistics** - Iterates entire cache on each getStatistics() call
4. **String interpolation for large prompts** - No lazy evaluation or streaming for context assembly

Secondary concerns:
- Single model for all queries (no tiering by complexity)
- Response cache uses simple string concatenation (potential key collisions)
- No semantic similarity matching for cache hits (only exact match)

## Current Milestone: M1 - Performance Foundation

**Goal:** Reduce command suggestion latency by 50% through targeted optimizations

**Focus Areas:**
1. Query embedding cache (LRU) to eliminate redundant Ollama calls
2. Semantic similarity cache matching (return cached responses for similar queries)
3. Model tiering (fast model for simple queries, full model for complex)
4. Incremental pruning (heap-based top-k instead of full sort)

**Success Criteria:**
- [ ] Cached/similar query response time < 200ms (currently ~2-3s)
- [ ] First query response time < 1.5s (currently ~2-3s)
- [ ] Memory usage remains under 100MB for typical workloads
- [ ] All existing tests pass
- [ ] No degradation in suggestion quality

## Architecture Decisions

### AD-001: Query Embedding Cache
- **Decision:** Add LRU cache for query embeddings in EmbeddingStore
- **Rationale:** Identical queries (e.g., "how do I list files") generate identical embeddings; caching prevents redundant Ollama API calls
- **Trade-off:** Memory vs latency; 1000-entry cache ~10MB overhead

### AD-002: Semantic Cache Matching
- **Decision:** Add cosine similarity matching to ResponseCache
- **Rationale:** Similar queries ("list files" vs "show files") should return cached responses when similarity > threshold
- **Trade-off:** Requires storing query embeddings alongside cached responses; may return less precise results

### AD-003: Model Tiering (Deferred to M2)
- **Status:** Research needed on model availability and performance characteristics
- **Approach:** Use smaller/faster model for simple queries, reserve full model for complex analysis

## Constraints

- **Swift 5.9+** - Must maintain compatibility
- **Ollama dependency** - All LLM operations go through local Ollama
- **Actor isolation** - Must preserve thread safety via actors
- **No external vector DB** - Keep file-based storage for simplicity (M1 scope)
- **Backward compatible** - Existing CLI commands must work unchanged

## Reference Materials

- `.planning/codebase/CONCERNS.md` - Performance bottlenecks audit
- `.planning/codebase/ARCHITECTURE.md` - Current system design
- `~/projects/knowledge-mcp` - RAG patterns for potential M2+ integration

## Tech Stack

- Swift 5.9+ with structured concurrency (actors)
- Ollama (local LLM inference + embeddings)
- Unix domain sockets (CLI ↔ daemon IPC)
- JSON file-based persistence

## Out of Scope (M1)

- External vector database integration (ChromaDB, Qdrant)
- Multi-model routing logic
- Streaming prompt construction
- CI/CD pipeline improvements
- Security hardening (covered in separate milestone)

---

*Last updated: 2026-01-23*

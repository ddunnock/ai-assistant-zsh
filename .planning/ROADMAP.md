# M1 Roadmap: Performance Foundation

**Milestone:** M1 - Performance Foundation
**Created:** 2026-01-23

## Phase Overview

| Phase | Name | Description | Status |
|-------|------|-------------|--------|
| 1 | Query Embedding Cache | LRU cache for query embeddings | Complete |
| 2 | Incremental Pruning | Heap-based top-k for memory/RAG stores | Complete |
| 3 | Semantic Cache Matching | Cosine similarity for cache hits | Complete |
| 4 | Statistics Optimization | Incremental counters for cache stats | Complete |
| 5 | M1 Cleanup | Wire orphaned stats, add missing verification docs | Planned |

---

## Phase 1: Query Embedding Cache

**Goal:** Eliminate redundant Ollama API calls for identical queries

**Plans:** 1 plan

Plans:
- [x] 01-01-PLAN.md - Implement LRU cache for query embeddings with SHA256 keys and metrics

**Requirements:**
- R1.1: Add LRU cache to EmbeddingStore with configurable max size (default: 1000)
- R1.2: Cache key = SHA256 hash of query text
- R1.3: Track cache hit/miss metrics for observability
- R1.4: Thread-safe implementation via actor isolation

**Affected Files:**
- `Sources/AIShellCore/RAG/EmbeddingStore.swift`

**Acceptance Criteria:**
- [x] Second identical query returns embedding from cache (no Ollama call)
- [x] Cache evicts oldest entries when limit reached
- [x] Metrics available: hits, misses, hit ratio

---

## Phase 2: Incremental Pruning

**Goal:** Replace inline sorting with heap-based pruning for cleaner, more maintainable code

**Plans:** 1 plan

Plans:
- [x] 02-01-PLAN.md - Update swift-collections to 1.1.0+, implement heap-based pruning in EmbeddingStore and MemoryStore

**Requirements:**
- R2.1: Replace array sort in `addDocument()` with heap-based pruning
- R2.2: Replace array sort in `addMemory()` with heap-based pruning
- R2.3: Use swift-collections Heap for standard top-k selection pattern

**Affected Files:**
- `Sources/AIShellCore/RAG/EmbeddingStore.swift` (lines 105-118)
- `Sources/AIShellCore/Memory/MemoryStore.swift` (lines 203-217)

**Acceptance Criteria:**
- [x] addDocument() uses heap-based pruning
- [x] addMemory() uses heap-based pruning
- [x] Pruning behavior unchanged (still keeps most recent/important)

---

## Phase 3: Semantic Cache Matching

**Goal:** Return cached responses for semantically similar queries

**Plans:** 2 plans

Plans:
- [x] 03-01-PLAN.md - Implement semantic matching with embedding storage and JSON-based cache keys
- [x] 03-02-PLAN.md - Wire semantic matching to request handlers (gap closure)

**Requirements:**
- R3.1: Store query embedding alongside cached response
- R3.2: On cache miss, compute cosine similarity against stored embeddings
- R3.3: Return cached response if similarity > configurable threshold (default: 0.92)
- R3.4: Update cache key generation to avoid string collision (use JSON or length-prefix)

**Affected Files:**
- `Sources/AIShellCore/Cache/ResponseCache.swift`
- `Sources/AIShellCore/Server/EnhancedRequestHandler.swift`
- `Sources/AIShellDaemon/DaemonService.swift`

**Dependencies:**
- Phase 1 (need embedding generation capability)

**Acceptance Criteria:**
- [x] "list files" and "show files" return same cached response
- [x] Dissimilar queries generate fresh responses
- [x] Cache key collisions eliminated (no pipe separator issues)

---

## Phase 4: Statistics Optimization

**Goal:** Make getStatistics() O(1) instead of O(n), plus LLM observability metrics

**Plans:** 1 plan

Plans:
- [x] 04-01-PLAN.md - Implement running counters, O(1) statistics, and LLM observability metrics (exactHits, semanticHits, missReasons)

**Requirements:**
- R4.1: Maintain running counters for age distribution buckets
- R4.2: Update counters incrementally on add/remove
- R4.3: Return pre-computed statistics without iteration
- R4.4: Track exactHits vs semanticHits for cache hit breakdown
- R4.5: Track detailed cache miss reasons for debugging

**Affected Files:**
- `Sources/AIShellCore/Cache/ResponseCache.swift` (lines 132-163)

**Acceptance Criteria:**
- [x] getStatistics() returns in constant time
- [x] Statistics accuracy unchanged from current implementation
- [x] exactHits and semanticHits tracked separately
- [x] Miss reasons categorized (no_match, expired, below_threshold, etc.)

---

## Phase 5: M1 Cleanup

**Goal:** Address tech debt from M1 audit — wire orphaned observability exports and add missing documentation

**Plans:** 1 plan

Plans:
- [ ] 05-01-PLAN.md — Wire EmbeddingStore stats to health endpoint, create verification docs for phases 1-2, human smoke test semantic matching

**Gap Closure:** Closes tech debt from v1-MILESTONE-AUDIT.md

**Requirements:**
- R5.1: Wire `EmbeddingStore.getCacheStatistics()` to health endpoint for embedding cache observability
- R5.2: Create VERIFICATION.md for Phase 1 (Query Embedding Cache)
- R5.3: Create VERIFICATION.md for Phase 2 (Incremental Pruning)
- R5.4: Human smoke test for semantic matching (manual verification)

**Affected Files:**
- `Sources/AIShellCore/Server/EnhancedRequestHandler.swift` (health endpoint)
- `.planning/phases/01-query-embedding-cache/01-01-VERIFICATION.md` (new)
- `.planning/phases/02-incremental-pruning/02-01-VERIFICATION.md` (new)

**Acceptance Criteria:**
- [ ] Health endpoint returns embedding cache statistics
- [ ] Phase 1 has VERIFICATION.md with truths verified
- [ ] Phase 2 has VERIFICATION.md with truths verified
- [ ] Semantic matching manually tested with similar queries

---

## Success Metrics

After M1 completion:
- **Cached query latency:** < 200ms (down from ~2-3s)
- **First query latency:** < 1.5s (slight improvement from reduced overhead)
- **Memory overhead:** < 15MB for caches (acceptable trade-off)

---

*Roadmap created: 2026-01-23*

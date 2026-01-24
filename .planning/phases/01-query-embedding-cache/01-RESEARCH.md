# Phase 1: Query Embedding Cache - Research

**Researched:** 2026-01-23
**Domain:** Swift actor-based LRU caching with SHA256 hashing
**Confidence:** HIGH

## Summary

This phase implements an LRU cache for query embeddings within the existing `EmbeddingStore` actor to eliminate redundant Ollama API calls for identical queries. The research confirms that Swift's actor model provides inherent thread-safety, eliminating the need for external locking mechanisms. The existing codebase already demonstrates established patterns for caching (ResponseCache), SHA256 hashing (via swift-crypto), and metrics collection (CacheStatistics) that should be followed for consistency.

The key insight is that swift-collections (OrderedDictionary) is already available as a transitive dependency in the project (v1.3.0), making it the ideal choice for O(1) LRU operations. The existing ResponseCache uses a Dictionary with weighted scoring for eviction, but for pure LRU semantics, OrderedDictionary is more appropriate and efficient.

**Primary recommendation:** Implement a private `QueryEmbeddingCache` actor (or embed cache directly in EmbeddingStore) using OrderedDictionary from swift-collections for O(1) LRU eviction, SHA256 from swift-crypto for cache keys, and follow the existing `CacheStatistics` pattern for metrics.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Actors | Swift 5.9+ | Thread-safe isolation | Built into Swift; already used by EmbeddingStore |
| swift-crypto (SHA256) | 3.15.1 | Cache key generation | Already in Package.swift; used by ResponseCache |
| swift-collections (OrderedDictionary) | 1.3.0 | LRU eviction ordering | Already transitive dependency; O(1) operations |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| swift-log | 1.6.4 | Logging | Already used via LoggerFactory |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| OrderedDictionary | Dictionary + Array | Simpler but O(n) for access updates |
| OrderedDictionary | nicklockwood/LRUCache | Sendable, but adds external dependency |
| OrderedDictionary | Dictionary + manual ordering | More code, same complexity |

**Installation:**
Already available. To explicitly import OrderedCollections, add to Package.swift:
```swift
.product(name: "OrderedCollections", package: "swift-collections"),
```

## Architecture Patterns

### Recommended Project Structure
```
Sources/AIShellCore/
├── Cache/
│   ├── ResponseCache.swift       # Existing - LLM response cache
│   └── EmbeddingCache.swift      # NEW - Optional if extracting from EmbeddingStore
├── RAG/
│   └── EmbeddingStore.swift      # MODIFY - Add cache + metrics
```

### Pattern 1: Actor-Internal LRU Cache
**What:** Embed the LRU cache directly within the EmbeddingStore actor
**When to use:** When cache is tightly coupled to a single actor (our case)
**Example:**
```swift
// Source: Project pattern + GitHub gist (eneko/LRUCacheActor)
public actor EmbeddingStore {
    // Existing properties...

    // Cache properties
    private var embeddingCache: OrderedDictionary<String, [Double]> = [:]
    private let maxCacheSize: Int
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    public func search(query: String, ...) async throws -> [SearchResult] {
        let cacheKey = createCacheKey(for: query)

        // Check cache first
        if let cached = getCachedEmbedding(for: cacheKey) {
            cacheHits += 1
            return searchWithEmbedding(cached, ...)
        }

        // Cache miss - generate embedding
        cacheMisses += 1
        let embedding = try await ollamaClient.generateEmbedding(text: query)
        setCachedEmbedding(embedding, for: cacheKey)

        return searchWithEmbedding(embedding, ...)
    }
}
```

### Pattern 2: SHA256 Cache Key Generation
**What:** Hash query text to create fixed-length cache keys
**When to use:** Always for text-based cache keys (consistent with ResponseCache)
**Example:**
```swift
// Source: ResponseCache.swift + Apple swift-crypto docs
import Crypto

private func createCacheKey(for query: String) -> String {
    let data = Data(query.utf8)
    let hash = SHA256.hash(data: data)
    return hash.compactMap { String(format: "%02x", $0) }.joined()
}
```

### Pattern 3: OrderedDictionary LRU Operations
**What:** Use OrderedDictionary's insertion-order semantics for LRU
**When to use:** When implementing LRU cache with O(1) access
**Example:**
```swift
// Source: GitHub gist (eneko/LRUCacheActor) + swift-collections docs
import OrderedCollections

// Read: Move to end (most recently used)
private func getCachedEmbedding(for key: String) -> [Double]? {
    guard let value = embeddingCache.removeValue(forKey: key) else {
        return nil
    }
    embeddingCache[key] = value  // Re-insert at end
    return value
}

// Write: Insert at end, evict from front if full
private func setCachedEmbedding(_ embedding: [Double], for key: String) {
    while embeddingCache.count >= maxCacheSize {
        embeddingCache.removeFirst()  // Remove oldest (LRU)
    }
    embeddingCache[key] = embedding
}
```

### Pattern 4: Cache Metrics (Following ResponseCache)
**What:** Track hits, misses, hit ratio for observability
**When to use:** Always for production caches
**Example:**
```swift
// Source: ResponseCache.swift pattern
public struct EmbeddingCacheStatistics {
    public let totalEntries: Int
    public let cacheHits: Int
    public let cacheMisses: Int
    public var hitRatio: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }
}

public func getCacheStatistics() -> EmbeddingCacheStatistics {
    return EmbeddingCacheStatistics(
        totalEntries: embeddingCache.count,
        cacheHits: cacheHits,
        cacheMisses: cacheMisses
    )
}
```

### Anti-Patterns to Avoid
- **Separate cache actor:** Don't create a separate actor for the cache; it adds unnecessary `await` overhead and complexity. Keep cache internal to EmbeddingStore.
- **Using NSCache:** NSCache evicts on memory pressure which is unpredictable; LRU with fixed size is more debuggable.
- **Storing embeddings with documents:** Query embeddings are ephemeral lookups, not persistent documents.
- **String keys directly:** Don't use raw query strings as keys; hash them for consistent length and memory efficiency.

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| LRU ordering | Custom doubly-linked list | OrderedDictionary | Already tested, O(1), available as dependency |
| SHA256 hashing | CommonCrypto bindings | swift-crypto SHA256 | Already in project, safer API |
| Thread safety | Manual locks/queues | Swift actors | Built-in, compiler-verified |
| Cache statistics | Custom counters | Follow CacheStatistics pattern | Consistency with ResponseCache |

**Key insight:** The project already has all the building blocks. The implementation should compose existing patterns, not invent new ones.

## Common Pitfalls

### Pitfall 1: Forgetting LRU Update on Cache Hit
**What goes wrong:** Cache becomes FIFO instead of LRU; frequently-used items get evicted
**Why it happens:** Developer only checks `if let value = cache[key]` without updating order
**How to avoid:** Always remove+reinsert on read to move item to end
**Warning signs:** Frequently-queried items not in cache; hit ratio unexpectedly low

### Pitfall 2: Actor Reentrancy Issues
**What goes wrong:** State changes during `await` cause inconsistent cache state
**Why it happens:** Between `await ollamaClient.generateEmbedding()` and cache write, another call might populate the same key
**How to avoid:** Check cache again after await; accept potential duplicate work (idempotent)
**Warning signs:** Duplicate Ollama calls for same query in logs

### Pitfall 3: Unbounded Memory Growth
**What goes wrong:** Embeddings are large (~4KB per 1024-dim vector); cache grows unbounded
**Why it happens:** Forgetting to set maxCacheSize or setting it too high
**How to avoid:** Default to 1000 (requirement R1.1); ~10MB overhead acceptable
**Warning signs:** Memory usage grows linearly with queries

### Pitfall 4: Cache Key Collisions
**What goes wrong:** Different queries return same embedding
**Why it happens:** SHA256 collision (astronomically unlikely) or normalization issues
**How to avoid:** Use UTF-8 encoding consistently; don't normalize query text
**Warning signs:** Wrong search results for specific queries

### Pitfall 5: Metrics Counter Overflow
**What goes wrong:** Hit/miss counters overflow after extended use
**Why it happens:** Using Int without considering 64-bit range
**How to avoid:** Int64 on 64-bit platforms handles ~9 quintillion; acceptable
**Warning signs:** Negative hit ratios (would require extreme usage)

## Code Examples

Verified patterns from official sources:

### Complete Cache Integration
```swift
// Source: Synthesized from ResponseCache.swift + swift-crypto docs + swift-collections
import Crypto
import OrderedCollections

public actor EmbeddingStore {
    // ... existing properties ...

    // Query embedding cache
    private var embeddingCache: OrderedDictionary<String, [Double]> = [:]
    private let maxCacheSize: Int
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    public init(
        storageURL: URL,
        ollamaClient: OllamaClient,
        maxCacheSize: Int = 1000  // R1.1: Default 1000
    ) {
        self.storageURL = storageURL
        self.ollamaClient = ollamaClient
        self.maxCacheSize = maxCacheSize
    }

    public func search(
        query: String,
        limit: Int = 5,
        minSimilarity: Double = 0.5,
        source: DocumentSource? = nil,
        workingDirectory: String? = nil
    ) async throws -> [SearchResult] {
        // R1.2: SHA256 hash of query text
        let cacheKey = createCacheKey(for: query)

        let queryEmbedding: [Double]

        // Check cache
        if let cached = getCachedEmbedding(for: cacheKey) {
            cacheHits += 1  // R1.3: Track hit
            queryEmbedding = cached
            logger.debug("Embedding cache hit", metadata: ["key": String(cacheKey.prefix(16))])
        } else {
            cacheMisses += 1  // R1.3: Track miss
            queryEmbedding = try await ollamaClient.generateEmbedding(text: query)
            setCachedEmbedding(queryEmbedding, for: cacheKey)
            logger.debug("Embedding cache miss", metadata: ["key": String(cacheKey.prefix(16))])
        }

        // ... rest of search logic with queryEmbedding ...
    }

    // R1.2: Cache key = SHA256 hash
    private func createCacheKey(for query: String) -> String {
        let data = Data(query.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    // R1.4: Thread-safe via actor isolation
    private func getCachedEmbedding(for key: String) -> [Double]? {
        guard let value = embeddingCache.removeValue(forKey: key) else {
            return nil
        }
        embeddingCache[key] = value  // Move to end (MRU)
        return value
    }

    // R1.1: LRU eviction when limit reached
    private func setCachedEmbedding(_ embedding: [Double], for key: String) {
        while embeddingCache.count >= maxCacheSize {
            embeddingCache.removeFirst()  // Evict oldest
        }
        embeddingCache[key] = embedding
    }

    // R1.3: Metrics
    public func getCacheStatistics() -> EmbeddingCacheStatistics {
        return EmbeddingCacheStatistics(
            totalEntries: embeddingCache.count,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses
        )
    }
}

public struct EmbeddingCacheStatistics {
    public let totalEntries: Int
    public let cacheHits: Int
    public let cacheMisses: Int

    public var hitRatio: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }
}
```

### Test Verification Pattern
```swift
// Source: Standard Swift testing pattern
func testCacheHitReturnsFromCache() async throws {
    let store = EmbeddingStore(
        storageURL: testURL,
        ollamaClient: mockClient,
        maxCacheSize: 10
    )

    // First call - cache miss
    _ = try await store.search(query: "test query")

    // Second call - should be cache hit (no Ollama call)
    mockClient.resetCallCount()
    _ = try await store.search(query: "test query")

    XCTAssertEqual(mockClient.embeddingCallCount, 0, "Should use cached embedding")

    let stats = await store.getCacheStatistics()
    XCTAssertEqual(stats.cacheHits, 1)
    XCTAssertEqual(stats.cacheMisses, 1)
    XCTAssertEqual(stats.hitRatio, 0.5, accuracy: 0.01)
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| NSLock/DispatchQueue | Swift Actors | Swift 5.5 (2021) | Compiler-verified thread safety |
| CommonCrypto | swift-crypto | 2020 | Safer, pure Swift API |
| Custom linked lists | OrderedDictionary | swift-collections 1.0 (2021) | Standard library quality |

**Deprecated/outdated:**
- **NSCache for LRU:** Evicts unpredictably on memory pressure; use OrderedDictionary
- **CommonCrypto:** Still works but swift-crypto is preferred for new code
- **Manual locking in actors:** Actors handle isolation; locks add overhead

## Open Questions

Things that couldn't be fully resolved:

1. **Persistence of cache across app restarts?**
   - What we know: Requirement doesn't mention persistence; ResponseCache has optional persistence
   - What's unclear: Should embedding cache persist like ResponseCache?
   - Recommendation: Start without persistence (in-memory only); can add later if needed

2. **Should addDocument() also cache embeddings?**
   - What we know: R1.1-R1.4 focus on query embeddings in search()
   - What's unclear: Document embeddings are also computed; could be cached
   - Recommendation: Implement for search() first (primary use case); can extend later

3. **Configurable cache size at runtime?**
   - What we know: R1.1 says "configurable max size (default: 1000)"
   - What's unclear: Configurable via init vs runtime adjustment
   - Recommendation: Init-time only (simpler); runtime adjustment adds complexity

## Sources

### Primary (HIGH confidence)
- `/Users/dunnock/projects/AIShellAssistant/Sources/AIShellCore/Cache/ResponseCache.swift` - Existing cache patterns, SHA256 usage, CacheStatistics
- `/Users/dunnock/projects/AIShellAssistant/Sources/AIShellCore/RAG/EmbeddingStore.swift` - Target file, actor structure
- `/Users/dunnock/projects/AIShellAssistant/Package.swift` - Dependencies, swift-crypto 3.0+
- `/Users/dunnock/projects/AIShellAssistant/Package.resolved` - swift-collections 1.3.0 available
- [Apple swift-crypto SHA256 docs](https://apple.github.io/swift-crypto/docs/current/Crypto/Structs/SHA256.html) - SHA256 API

### Secondary (MEDIUM confidence)
- [GitHub Gist: LRUCacheActor](https://gist.github.com/eneko/c8b92a6005ad8e669ced69509575e361) - Actor-based LRU pattern with OrderedDictionary
- [SwiftLee: Actor Isolation](https://www.avanderlee.com/swift/nonisolated-isolated/) - Actor isolation patterns

### Tertiary (LOW confidence)
- [nicklockwood/LRUCache](https://github.com/nicklockwood/LRUCache) - Alternative library (not using, but validated approach)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All libraries already in project, verified via Package.resolved
- Architecture: HIGH - Follows existing ResponseCache patterns
- Pitfalls: MEDIUM - Based on general LRU cache knowledge, verified against actor semantics

**Research date:** 2026-01-23
**Valid until:** 2026-02-23 (30 days - stable domain)

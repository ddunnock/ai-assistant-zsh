# Phase 4: Statistics Optimization - Research

**Researched:** 2026-01-24
**Domain:** O(1) statistics with running counters, LLM observability metrics, Swift actor-based counter patterns
**Confidence:** HIGH

## Summary

This phase optimizes the ResponseCache `getStatistics()` method from O(n) to O(1) by maintaining running counters that are updated incrementally on add/remove operations. The scope extends beyond the original performance goal to include LLM observability metrics inspired by LangFuse patterns: exact vs semantic hit tracking, detailed cache miss reasons, and query type breakdown.

The current implementation iterates through all cache entries to calculate age distribution buckets (< 1h, < 1d, < 7d, > 7d) and total hit counts on every call. For a cache with 500 entries, this is 500 operations per statistics request. The optimization moves this work to cache mutation time, where each add/remove updates bucket counters synchronously, making statistics retrieval a simple property access.

A critical challenge is **bucket drift**: as time passes, entries age from one bucket to another without any add/remove event triggering a counter update. The user decision mandates lazy recalculation with throttling—recalculate on `getStatistics()` calls when counters are stale (>5 minutes old), but cache the recalculated values to avoid repeated O(n) scans. This balances accuracy (buckets reflect current state) with performance (amortized O(1) for most calls).

The observability metrics expansion requires tracking exact vs semantic cache hits (to measure Phase 3's semantic matching effectiveness) and detailed miss reasons (no_match, expired, below_threshold, no_embedding, empty_cache, query_too_short). Swift actors provide thread-safe counter updates without manual locking, and the existing logger infrastructure supports structured metadata for debugging.

**Primary recommendation:** Add a `CacheCounters` struct with running totals (totalEntries, totalHits, exactHits, semanticHits, ageBuckets, missReasons), update counters synchronously in `set()`, `get()`, `invalidate()`, and `pruneCache()`, implement lazy recalculation with 5-minute throttle for age bucket drift, and extend `CacheStatistics` to include observability metrics.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| Swift Actors | Swift 5.9+ | Thread-safe counter updates | Already used in ResponseCache for state isolation |
| Foundation Date | Built-in | Timestamp comparison for throttling | Standard Swift time operations |
| Swift Logging | 1.5.0+ | Structured metadata logging | Already used for cache operations |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| Swift Collections | 1.1.0+ | Dictionary for bucket counters | Already in Package.swift |
| os.log | Built-in | Performance-critical logging | Optional for high-frequency counter updates |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| Lazy recalculation | Continuous bucket updates (timer) | Background work, but wastes CPU when stats not needed |
| 5-minute throttle | Adaptive throttle (based on cache churn) | More complex, minor accuracy gains |
| Running counters | Snapshot-on-demand with caching | Same O(n) recalc, just cached; doesn't solve root cause |
| Separate CacheMetrics | Extend CacheStatistics | Separate type is cleaner for observability vs core stats |

**No new dependencies required.** All necessary components already exist in the project.

## Architecture Patterns

### Recommended Project Structure
```
Sources/AIShellCore/
├── Cache/
│   └── ResponseCache.swift        # MODIFY - Add CacheCounters, update mutation methods
└── Models/
    └── (inline modifications)     # Extend CacheStatistics struct
```

### Pattern 1: Running Counter Struct
**What:** Encapsulate all counters in a mutable struct within the actor
**When to use:** When you need O(1) statistics without iterating collections
**Example:**
```swift
// Source: Industry pattern for real-time metrics
private struct CacheCounters {
    var totalEntries: Int = 0
    var totalHits: Int = 0
    var exactHits: Int = 0        // Phase 3 semantic cache tracking
    var semanticHits: Int = 0     // Phase 3 semantic cache tracking
    var ageBuckets: [String: Int] = [
        "< 1h": 0,
        "< 1d": 0,
        "< 7d": 0,
        "> 7d": 0
    ]
    var missReasons: [String: Int] = [
        "no_match": 0,
        "expired": 0,
        "below_threshold": 0,
        "no_embedding": 0,
        "empty_cache": 0,
        "query_too_short": 0
    ]
    var lastRecalculated: Date = Date()
}
```

### Pattern 2: Lazy Recalculation with Throttle
**What:** Recalculate age buckets on `getStatistics()` calls, but throttle to max once per 5 minutes
**When to use:** When counters drift over time without triggering update events
**Example:**
```swift
// Source: Throttle pattern from Swift async-algorithms
private let recalcInterval: TimeInterval = 300  // 5 minutes

public func getStatistics() -> CacheStatistics {
    // Check if recalculation needed (bucket drift)
    let now = Date()
    if now.timeIntervalSince(counters.lastRecalculated) > recalcInterval {
        recalculateAgeBuckets()
        counters.lastRecalculated = now
    }

    // O(1) return from counters
    return CacheStatistics(
        totalEntries: counters.totalEntries,
        totalHits: counters.totalHits,
        exactHits: counters.exactHits,
        semanticHits: counters.semanticHits,
        ageDistribution: counters.ageBuckets,
        missReasons: counters.missReasons
    )
}

private func recalculateAgeBuckets() {
    // Reset age buckets
    counters.ageBuckets = ["< 1h": 0, "< 1d": 0, "< 7d": 0, "> 7d": 0]

    // O(n) scan - but throttled to every 5 minutes
    let now = Date()
    for entry in cache.values {
        let age = now.timeIntervalSince(entry.timestamp)
        if age < 3600 {
            counters.ageBuckets["< 1h"]! += 1
        } else if age < 86400 {
            counters.ageBuckets["< 1d"]! += 1
        } else if age < 86400 * 7 {
            counters.ageBuckets["< 7d"]! += 1
        } else {
            counters.ageBuckets["> 7d"]! += 1
        }
    }
}
```

### Pattern 3: Synchronous Counter Updates on Mutations
**What:** Update counters immediately when cache state changes
**When to use:** For all cache add/remove/hit operations
**Example:**
```swift
// Source: Standard counter update pattern
public func set(
    _ key: String,
    response: String,
    query: String? = nil,
    metadata: [String: String] = [:]
) async {
    // Generate embedding (existing code)...

    let entry = CachedResponse(...)

    // Calculate age bucket for new entry
    let ageBucket = "< 1h"  // New entries always start in freshest bucket

    // Update counters before cache insertion
    let isNew = cache[key] == nil
    if isNew {
        counters.totalEntries += 1
        counters.ageBuckets[ageBucket]! += 1
    }

    cache[key] = entry

    // Prune if needed (updates counters internally)
    if cache.count > maxCacheSize {
        pruneCache()
    }
}

public func get(_ key: String, query: String? = nil) async -> String? {
    // Level 1: Exact match
    if let entry = cache[key] {
        if !isExpired(entry) {
            // Increment hit counters
            counters.totalHits += 1
            counters.exactHits += 1

            // Update entry hit count (existing code)...
            return entry.response
        } else {
            // Track expiration as miss reason
            counters.missReasons["expired"]! += 1
            cache.removeValue(forKey: key)
            counters.totalEntries -= 1
            // Decrement age bucket (would require tracking which bucket)
        }
    }

    // Level 2: Semantic match
    if enableSemanticCache, let query = query {
        if let result = await findSimilarMatch(query: query) {
            counters.totalHits += 1
            counters.semanticHits += 1
            return result
        }
    }

    // Track miss reason
    if cache.isEmpty {
        counters.missReasons["empty_cache"]! += 1
    } else if query == nil {
        counters.missReasons["no_query"]! += 1
    } else {
        counters.missReasons["no_match"]! += 1
    }

    return nil
}
```

### Pattern 4: Extended CacheStatistics for Observability
**What:** Expand statistics struct to include LLM-specific observability metrics
**When to use:** When exposing metrics for monitoring and debugging
**Example:**
```swift
// Source: LangFuse observability patterns
public struct CacheStatistics {
    // Core statistics (existing)
    public let totalEntries: Int
    public let totalHits: Int
    public let ageDistribution: [String: Int]

    // LLM observability metrics (new)
    public let exactHits: Int         // Cache hits via exact key match
    public let semanticHits: Int      // Cache hits via semantic similarity
    public let missReasons: [String: Int]  // Breakdown of why cache missed

    // Derived metrics
    public var hitRate: Double {
        let totalRequests = totalHits + missReasons.values.reduce(0, +)
        return totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0.0
    }

    public var semanticHitRate: Double {
        return totalHits > 0 ? Double(semanticHits) / Double(totalHits) : 0.0
    }
}
```

### Pattern 5: Age Bucket Management with Drift Awareness
**What:** Track which bucket each entry belongs to, update on recalculation
**When to use:** When bucket assignments change over time without add/remove
**Example:**
```swift
// Option 1: Store bucket with entry (accurate but adds memory)
public struct CachedResponse: Codable {
    // Existing fields...
    private var cachedAgeBucket: String?  // Memoized bucket
}

// Option 2: Recalculate buckets lazily (current approach - simpler)
// Don't track per-entry bucket, just recalculate all buckets every 5 minutes
// Tradeoff: Less accurate between recalculations, but simpler implementation
```

### Anti-Patterns to Avoid

- **Tracking per-entry age bucket on every access:** Creates O(n) work to update buckets as entries age; defeats O(1) goal
- **Continuous background recalculation:** Wastes CPU when statistics aren't being requested; lazy is better
- **Throttle < 1 minute:** Too frequent O(n) scans; 5 minutes balances accuracy and performance
- **Throttle > 30 minutes:** Age buckets become too stale; defeats observability value
- **Counter updates without actor isolation:** Data races; Swift actors make this safe by default
- **Forgetting to decrement counters on removal:** Counters drift from actual state; invalidate() and pruneCache() must update
- **Miss reason tracking at handler level:** Couples handler to cache implementation; track at cache level where decision is made

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Timestamp-based throttling | Custom throttle logic | Apple swift-async-algorithms throttle | Handles suspension points, tested |
| Counter synchronization | Manual locks | Swift actor isolation | Race-free by construction |
| Age bucket calculation | Complex date math | TimeInterval comparisons | Built-in, clear, tested |
| Statistics serialization | Custom format | Extend existing Codable | Consistent with save/load pattern |
| Miss reason categorization | Ad-hoc strings | Enum with exhaustive switch | Compile-time safety, prevents typos |

**Key insight:** Swift actors already provide thread-safe counter updates without manual locking. The throttle pattern from swift-async-algorithms can be adapted for the 5-minute recalculation requirement. Don't reinvent these wheels.

## Common Pitfalls

### Pitfall 1: Bucket Drift Without Recalculation
**What goes wrong:** Entry added at 12:00pm goes into "< 1h" bucket; at 2:00pm it should be in "< 1d" but counter still shows "< 1h"
**Why it happens:** No event triggers bucket reassignment as time passes
**How to avoid:** Lazy recalculation on `getStatistics()` with 5-minute throttle; accept slight staleness between recalcs
**Warning signs:** Age distribution doesn't change over time; all entries appear fresh

### Pitfall 2: Forgetting to Update Counters on Pruning
**What goes wrong:** `pruneCache()` removes entries but doesn't decrement `totalEntries` or age buckets; counters grow unbounded
**Why it happens:** Pruning is a removal operation but may not be obvious
**How to avoid:** Track which entries are removed in `pruneCache()`, decrement counters for each
**Warning signs:** `totalEntries` > `cache.count`; counters never decrease

### Pitfall 3: Race Conditions in Counter Updates
**What goes wrong:** Multiple tasks update counters concurrently; final counts are incorrect
**Why it happens:** Not using actor isolation for counter access
**How to avoid:** Keep counters as private actor-isolated state; all updates happen within actor methods
**Warning signs:** Counters occasionally wrong; Xcode thread sanitizer warnings

### Pitfall 4: Miss Reason Double-Counting
**What goes wrong:** Cache miss increments "no_match", then semantic fallback also increments "below_threshold"; same miss counted twice
**Why it happens:** Multiple code paths tracking the same miss event
**How to avoid:** Track miss reason at single point of failure; use early return pattern to prevent fallthrough
**Warning signs:** Sum of missReasons > actual misses; hit rate < expected

### Pitfall 5: Expensive Recalculation on Every getStatistics() Call
**What goes wrong:** Forgot to check `lastRecalculated` timestamp; every call does O(n) scan
**Why it happens:** Throttle logic not implemented or bypassed
**How to avoid:** Always check `now.timeIntervalSince(lastRecalculated) > recalcInterval` before recalculating
**Warning signs:** High CPU on getStatistics() calls; p95 latency > 50ms

### Pitfall 6: Age Bucket Boundaries Off-by-One
**What goes wrong:** Entry exactly 1 hour old goes into wrong bucket (< 1h vs < 1d)
**Why it happens:** Using `<=` vs `<` inconsistently
**How to avoid:** Use consistent comparison operators; document bucket boundaries clearly
**Warning signs:** Bucket totals don't sum to totalEntries; edge case queries give unexpected results

### Pitfall 7: Memory Overhead from Tracking Too Much
**What goes wrong:** Tracking 50+ miss reason categories creates large counter dict; high memory overhead
**Why it happens:** Over-engineering observability without clear use case
**How to avoid:** Start with 6-8 core miss reasons; expand only when debugging specific issues
**Warning signs:** CacheCounters struct > 1KB; counters dominate cache memory usage

## Code Examples

Verified patterns from official sources:

### Complete CacheCounters Implementation
```swift
// Source: Running counter pattern + LangFuse observability metrics
private struct CacheCounters {
    // Core statistics
    var totalEntries: Int = 0
    var totalHits: Int = 0

    // LLM observability (Phase 4 extension)
    var exactHits: Int = 0
    var semanticHits: Int = 0

    // Age distribution buckets
    var ageBuckets: [String: Int] = [
        "< 1h": 0,
        "< 1d": 0,
        "< 7d": 0,
        "> 7d": 0
    ]

    // Cache miss reasons (LLM observability)
    var missReasons: [String: Int] = [
        "no_match": 0,        // No exact or semantic match found
        "expired": 0,         // Entry existed but expired
        "below_threshold": 0, // Semantic similarity < threshold
        "no_embedding": 0,    // Query has no embedding for semantic search
        "empty_cache": 0,     // Cache is empty
        "query_too_short": 0  // Query too short to generate embedding
    ]

    // Throttle state
    var lastRecalculated: Date = Date()
}
```

### Modified ResponseCache with O(1) Statistics
```swift
// Source: Synthesized from ResponseCache.swift + running counter patterns
public actor ResponseCache {
    private var cache: [String: CachedResponse] = [:]
    private var counters = CacheCounters()

    private let recalcInterval: TimeInterval = 300  // 5 minutes

    // MARK: - O(1) Statistics

    public func getStatistics() -> CacheStatistics {
        // Lazy recalculation if stale (>5 minutes)
        let now = Date()
        if now.timeIntervalSince(counters.lastRecalculated) > recalcInterval {
            recalculateAgeBuckets()
            counters.lastRecalculated = now
        }

        // O(1) return from counters
        return CacheStatistics(
            totalEntries: counters.totalEntries,
            totalHits: counters.totalHits,
            exactHits: counters.exactHits,
            semanticHits: counters.semanticHits,
            ageDistribution: counters.ageBuckets,
            missReasons: counters.missReasons
        )
    }

    private func recalculateAgeBuckets() {
        // Reset buckets
        counters.ageBuckets = ["< 1h": 0, "< 1d": 0, "< 7d": 0, "> 7d": 0]

        // O(n) scan - but throttled to every 5 minutes max
        let now = Date()
        for entry in cache.values {
            let age = now.timeIntervalSince(entry.timestamp)
            let bucket = ageBucket(for: age)
            counters.ageBuckets[bucket]! += 1
        }
    }

    private func ageBucket(for age: TimeInterval) -> String {
        if age < 3600 {
            return "< 1h"
        } else if age < 86400 {
            return "< 1d"
        } else if age < 86400 * 7 {
            return "< 7d"
        } else {
            return "> 7d"
        }
    }

    // MARK: - Counter Updates on Mutations

    public func set(
        _ key: String,
        response: String,
        query: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        // Generate embedding (existing code)...
        var embedding: [Double]? = nil
        if enableSemanticCache, let query = query, let client = ollamaClient {
            do {
                embedding = try await client.generateEmbedding(text: query)
            } catch {
                logger.warning("Failed to generate embedding")
            }
        }

        let entry = CachedResponse(
            key: key,
            response: response,
            metadata: metadata,
            embedding: embedding,
            originalQuery: query
        )

        // Update counters
        let isNew = cache[key] == nil
        if isNew {
            counters.totalEntries += 1
            counters.ageBuckets["< 1h"]! += 1  // New entries start in freshest bucket
        }

        cache[key] = entry

        // Prune if needed
        if cache.count > maxCacheSize {
            pruneCache()
        }
    }

    public func get(_ key: String, query: String? = nil) async -> String? {
        // Level 1: Exact match
        if let entry = cache[key] {
            if !isExpired(entry) {
                // Update hit counters
                counters.totalHits += 1
                counters.exactHits += 1

                // Update entry (existing code)...
                let updated = CachedResponse(
                    key: entry.key,
                    response: entry.response,
                    timestamp: entry.timestamp,
                    hitCount: entry.hitCount + 1,
                    metadata: entry.metadata,
                    embedding: entry.embedding,
                    originalQuery: entry.originalQuery
                )
                cache[key] = updated

                return entry.response
            } else {
                // Track expiration
                counters.missReasons["expired"]! += 1
                cache.removeValue(forKey: key)
                counters.totalEntries -= 1
                // Note: Age bucket decrement handled in recalculateAgeBuckets()
            }
        }

        // Level 2: Semantic match
        if enableSemanticCache, let query = query, ollamaClient != nil {
            if let result = await findSimilarMatch(query: query) {
                counters.totalHits += 1
                counters.semanticHits += 1
                return result
            }
        }

        // Track miss reason
        if cache.isEmpty {
            counters.missReasons["empty_cache"]! += 1
        } else if query == nil {
            counters.missReasons["no_embedding"]! += 1
        } else {
            counters.missReasons["no_match"]! += 1
        }

        return nil
    }

    private func pruneCache() {
        let before = cache.count

        // Sort and keep top entries (existing logic)...
        let sorted = cache.values.sorted { entry1, entry2 in
            calculateScore(entry1) > calculateScore(entry2)
        }
        let toKeep = sorted.prefix(maxCacheSize)
        cache = Dictionary(uniqueKeysWithValues: toKeep.map { ($0.key, $0) })

        // Update counter
        let removed = before - cache.count
        counters.totalEntries -= removed
        // Note: Age bucket decrement handled in recalculateAgeBuckets()
    }

    public func invalidate(_ key: String) {
        if cache.removeValue(forKey: key) != nil {
            counters.totalEntries -= 1
            // Note: Age bucket decrement handled in recalculateAgeBuckets()
        }
    }
}
```

### Extended CacheStatistics
```swift
// Source: LangFuse observability patterns
public struct CacheStatistics {
    // Core statistics (existing)
    public let totalEntries: Int
    public let totalHits: Int
    public let ageDistribution: [String: Int]

    // LLM observability metrics (new)
    public let exactHits: Int
    public let semanticHits: Int
    public let missReasons: [String: Int]

    public init(
        totalEntries: Int,
        totalHits: Int,
        exactHits: Int = 0,
        semanticHits: Int = 0,
        ageDistribution: [String: Int],
        missReasons: [String: Int] = [:]
    ) {
        self.totalEntries = totalEntries
        self.totalHits = totalHits
        self.exactHits = exactHits
        self.semanticHits = semanticHits
        self.ageDistribution = ageDistribution
        self.missReasons = missReasons
    }

    // Derived metrics for observability
    public var hitRate: Double {
        let totalRequests = totalHits + missReasons.values.reduce(0, +)
        return totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0.0
    }

    public var semanticHitRate: Double {
        return totalHits > 0 ? Double(semanticHits) / Double(totalHits) : 0.0
    }

    public var cacheMissRate: Double {
        return 1.0 - hitRate
    }
}
```

### findSimilarMatch with Miss Reason Tracking
```swift
// Source: Modified from Phase 3 with observability
private func findSimilarMatch(query: String) async -> String? {
    guard let client = ollamaClient else {
        counters.missReasons["no_embedding"]! += 1
        return nil
    }

    // Generate embedding
    let queryEmbedding: [Double]
    do {
        queryEmbedding = try await client.generateEmbedding(text: query)
    } catch {
        counters.missReasons["no_embedding"]! += 1
        return nil
    }

    // Scan cache
    var bestMatch: (entry: CachedResponse, similarity: Double)?
    for entry in cache.values {
        guard !isExpired(entry) else { continue }
        guard let entryEmbedding = entry.embedding else { continue }

        let similarity = cosineSimilarity(queryEmbedding, entryEmbedding)
        if similarity >= semanticThreshold {
            if bestMatch == nil || similarity > bestMatch!.similarity {
                bestMatch = (entry, similarity)
            }
        }
    }

    // Return best match or track miss reason
    if let match = bestMatch {
        // Update hit count (existing code)...
        let updated = CachedResponse(...)
        cache[match.entry.key] = updated

        // Note: Caller increments totalHits and semanticHits
        return match.entry.response
    } else {
        // Track why semantic match failed
        let hasCandidates = cache.values.contains { $0.embedding != nil && !isExpired($0) }
        if hasCandidates {
            counters.missReasons["below_threshold"]! += 1
        } else {
            counters.missReasons["no_match"]! += 1
        }
        return nil
    }
}
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| O(n) statistics on demand | Running counters with lazy recalc | 2024-2025 | Sub-millisecond stats retrieval |
| Hit count only | Exact vs semantic hit breakdown | 2025 (LangFuse, GPTCache) | Measures semantic cache effectiveness |
| Generic cache metrics | LLM-specific observability | 2025 (LangFuse patterns) | Debuggable cache behavior |
| Manual counter synchronization | Swift actor isolation | Swift 5.5+ (2021) | Race-free by construction |
| Continuous recalculation | Lazy recalc with throttle | Emerging best practice | Balances accuracy and CPU usage |

**Deprecated/outdated:**
- **O(n) statistics calculation:** Unacceptable for hot paths; use running counters
- **Single "cache hits" counter:** Doesn't distinguish exact vs semantic; loses insight from Phase 3
- **No miss reason tracking:** Can't debug why cache isn't hitting; observability blind spot
- **Manual locks for counters:** Error-prone; Swift actors make this obsolete

**Emerging (not implementing now):**
- **Histogram-based age tracking:** Track age distribution with configurable bucket sizes (e.g., Prometheus histograms)
- **P50/P95/P99 latency tracking:** Measure cache operation latency percentiles
- **Adaptive throttle:** Adjust recalculation frequency based on cache churn rate

## Open Questions

Things that couldn't be fully resolved:

1. **Should age buckets be recalculated incrementally?**
   - What we know: 5-minute lazy recalc is O(n) but throttled; acceptable for 500 entries
   - What's unclear: Whether incremental bucket updates (on each access) would be faster
   - Recommendation: Start with lazy recalc (simpler). Profile if >50ms p95. Consider incremental updates (track bucket per entry) only if profiling shows bottleneck.

2. **How to handle counter persistence?**
   - What we know: Cache is persisted to JSON; counters could be saved too
   - What's unclear: Whether counters should persist across daemon restarts or reset to zero
   - Recommendation: Don't persist counters (reset on load). Simplifies consistency; counters rebuilt as cache warms up. Add persistence later if metrics history needed.

3. **Miss reason granularity?**
   - What we know: User wants "detailed breakdown" but didn't specify categories
   - What's unclear: Exact list of miss reasons; balance detail vs complexity
   - Recommendation: Start with 6 core reasons (no_match, expired, below_threshold, no_embedding, empty_cache, query_too_short). Expand based on debugging needs.

4. **Should pruned vs invalidated removals be tracked separately?**
   - What we know: User marked this as "Claude's discretion"
   - What's unclear: Whether distinguishing pruned (LRU eviction) from invalidated (manual removal) adds value
   - Recommendation: Don't distinguish for now. Track total removes. Add pruned/invalidated breakdown only if needed for capacity planning.

5. **Query type tracking at cache vs handler level?**
   - What we know: User decided "handler level (EnhancedRequestHandler), not cache level"
   - What's unclear: How handler communicates query type to cache statistics
   - Recommendation: Don't track query type in cache. Handler can log request type separately. If needed later, pass metadata through cache.set() context parameter.

## Sources

### Primary (HIGH confidence)
- `/Users/dunnock/projects/AIShellAssistant/Sources/AIShellCore/Cache/ResponseCache.swift` - Current O(n) getStatistics() implementation
- `/Users/dunnock/projects/AIShellAssistant/.planning/phases/04-statistics-optimization/04-CONTEXT.md` - User decisions and requirements
- [LangFuse: Model Usage & Cost Tracking](https://langfuse.com/docs/observability/features/token-and-cost-tracking) - Cache token tracking, miss reasons
- [LangFuse: Open Source LLM Metrics](https://langfuse.com/docs/metrics/overview) - Quality, cost, latency, volume metrics
- [Catchpoint: Semantic Caching Metrics](https://www.catchpoint.com/blog/semantic-caching-what-we-measured-why-it-matters) - Cache hit/miss rates, similarity scores, latency differential

### Secondary (MEDIUM confidence)
- [Swift Concurrency Guide (Medium)](https://medium.com/@thakurneeshu280/the-complete-guide-to-swift-concurrency-from-threading-to-actors-in-swift-6-a9cf006a19ac) - Swift 6 actor patterns
- [Swift 6 Concurrency Guide (Medium)](https://medium.com/@gauravios/swift-6-concurrency-a-practical-guide-for-ios-developers-27dee88b1adc) - Actor best practices
- [Apple swift-async-algorithms: Throttle](https://github.com/apple/swift-async-algorithms/blob/main/Sources/AsyncAlgorithms/AsyncAlgorithms.docc/Guides/Throttle.md) - Throttle pattern for lazy recalc
- [SwiftThrottle GitHub](https://github.com/Lakr233/SwiftThrottle) - Timestamp-based throttling
- [Redis: Cache Hit Ratio Strategy](https://redis.io/blog/why-your-cache-hit-ratio-strategy-needs-an-update/) - Cache metrics best practices
- [DeepLearning.AI: Semantic Caching Effectiveness](https://learn.deeplearning.ai/courses/semantic-caching-for-ai-agents/lesson/puufb0/measuring-cache-effectiveness) - Measuring cache hit rates
- [Reintech: LLM Caching Metrics](https://reintech.io/blog/how-to-implement-llm-caching-strategies-for-faster-response-times) - Hit rate, latency, memory utilization

### Tertiary (LOW confidence)
- [Digma: Cache Miss Observability](https://digma.ai/how-to-detect-cache-misses-using-observability/) - Miss detection patterns
- [PlanetScale: Slotted Counter Pattern](https://planetscale.com/blog/the-slotted-counter-pattern) - Distributed counter pattern (not needed for single-actor cache)

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - All components already in project (Swift actors, Foundation Date)
- Architecture: HIGH - Running counter pattern is well-established, Swift actor isolation is proven
- Pitfalls: HIGH - Bucket drift, counter consistency, and throttle patterns are well-documented
- Observability metrics: MEDIUM - LangFuse patterns are authoritative, but exact miss reason categories are Claude's discretion

**Research date:** 2026-01-24
**Valid until:** 2026-02-24 (30 days - stable domain, established patterns)

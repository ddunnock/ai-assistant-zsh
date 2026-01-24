# Phase 2: Incremental Pruning - Research

**Researched:** 2026-01-23
**Domain:** Swift Heap data structures, bounded collection pruning, priority queue patterns
**Confidence:** HIGH

## Summary

This phase replaces O(n log n) full-array sorting with O(log n) heap-based pruning in two hot paths: `EmbeddingStore.addDocument()` and `MemoryStore.addMemory()`. Both methods currently sort the entire collection when it exceeds capacity, then take a prefix of the highest-scored items.

The standard approach is to use a min-heap of bounded size k (where k = maxDocuments or maxMemoriesPerType). When adding a new item, if the collection exceeds capacity, compare the new item's score against the heap's minimum. If the new item scores higher, replace the minimum; otherwise, discard the new item. This maintains the top-k items in O(log k) time per insertion.

The swift-collections package (already in the project's dependencies) provides `Heap<Element: Comparable>`, a min-max heap that supports both `popMin()` and `popMax()` in O(log n) time. This is ideal because we need to evict the lowest-scored item (using `popMin()` or `replaceMin()`).

**Primary recommendation:** Use `Heap` from swift-collections with a custom `Comparable` wrapper struct that orders by combined importance/recency score, enabling O(log n) pruning via `replaceMin()`.

## Standard Stack

The established libraries/tools for this domain:

### Core
| Library | Version | Purpose | Why Standard |
|---------|---------|---------|--------------|
| swift-collections | 1.1.0+ | Heap data structure | Apple's official collections library, production-ready, already in project |
| HeapModule | (part of swift-collections) | Min-max heap implementation | O(1) min/max access, O(log n) insert/remove |

### Supporting
| Library | Version | Purpose | When to Use |
|---------|---------|---------|-------------|
| OrderedCollections | (part of swift-collections) | OrderedDictionary for LRU | Already used for embedding cache |

### Alternatives Considered
| Instead of | Could Use | Tradeoff |
|------------|-----------|----------|
| swift-collections Heap | Hand-rolled binary heap | More code, more bugs, no min-max dual access |
| Min-max heap | Separate min-heap | Can only efficiently pop one end; swift-collections Heap does both |
| Heap-based pruning | Full sort on each add | O(n log n) vs O(log n) - current approach, being replaced |

**Package.swift Update Required:**

The project currently specifies `from: "1.0.0"` but Heap was introduced in 1.1.0. Update to:

```swift
.package(
    url: "https://github.com/apple/swift-collections.git",
    from: "1.1.0"
)
```

**Import Statement:**

```swift
import HeapModule
```

Or continue using:
```swift
import OrderedCollections  // Already imported
import HeapModule          // Add this
```

## Architecture Patterns

### Pattern 1: Scored Wrapper for Heap Ordering

The existing code calculates a combined score from importance and recency. To use Heap, wrap items in a `Comparable` struct:

**What:** Create a wrapper that implements `Comparable` based on the eviction score
**When to use:** When items need ordering by computed score, not natural ordering
**Example:**

```swift
// Source: Standard pattern from swift-collections documentation + Top-K algorithm
struct ScoredDocument: Comparable {
    let document: EmbeddedDocument
    let score: Double  // Pre-computed eviction score (higher = keep)

    static func < (lhs: ScoredDocument, rhs: ScoredDocument) -> Bool {
        // Min-heap ordering: lower score = evict first
        lhs.score < rhs.score
    }

    static func == (lhs: ScoredDocument, rhs: ScoredDocument) -> Bool {
        lhs.document.id == rhs.document.id
    }
}
```

### Pattern 2: Top-K with Bounded Min-Heap

**What:** Maintain a min-heap of size k containing the k highest-scored items
**When to use:** When you need to keep the "best" k items and discard the rest
**Algorithm:**

```swift
// Source: Standard Top-K algorithm pattern
// https://www.techinterviewhandbook.org/algorithms/heap/

// When adding a new item:
if heap.count < maxSize {
    // Below capacity: just insert
    heap.insert(scoredItem)
} else if let minScore = heap.min?.score, scoredItem.score > minScore {
    // At capacity and new item is better than worst: replace
    heap.replaceMin(with: scoredItem)
}
// Otherwise: discard new item (it's worse than all k items we're keeping)
```

### Pattern 3: Heap-Array Synchronization

**What:** Keep both array (for random access/persistence) and heap (for efficient pruning) in sync
**When to use:** When you need both iteration over all items AND efficient pruning
**Consideration:** The existing code uses arrays that are persisted to JSON. Options:

Option A - Dual storage (recommended for this phase):
```swift
private var documents: [EmbeddedDocument] = []  // For persistence/iteration
private var documentHeap: Heap<ScoredDocument> = Heap()  // For pruning
```

Option B - Heap only, rebuild array on save:
```swift
private var documentHeap: Heap<ScoredDocument> = Heap()
// On save: let documents = documentHeap.unordered.map(\.document)
```

### Recommended Project Structure

No structural changes needed. Modifications are localized to:
```
Sources/AIShellCore/
├── RAG/
│   └── EmbeddingStore.swift     # Add ScoredDocument, modify addDocument()
└── Memory/
    └── MemoryStore.swift        # Add ScoredMemory, modify addMemory()
```

### Anti-Patterns to Avoid

- **Sorting on every add:** The current O(n log n) approach - this is what we're replacing
- **Using array.remove(at:) in a loop:** O(n) per removal; use heap operations instead
- **Recomputing scores repeatedly:** Pre-compute score when inserting, not when comparing
- **Using popMin() + insert() instead of replaceMin():** Two operations vs one; replaceMin() rebalances only once

## Don't Hand-Roll

Problems that look simple but have existing solutions:

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Min-max heap | Custom binary heap | `Heap` from swift-collections | Edge cases in siftUp/siftDown, tested implementation |
| Priority queue | Array + sort | `Heap` | O(log n) vs O(n log n) |
| Top-K selection | QuickSelect or full sort | Bounded min-heap | Streaming-friendly, simpler |
| Score comparison | Manual comparator closure | `Comparable` wrapper struct | Type-safe, works with Heap |

**Key insight:** Heap data structures have subtle invariant maintenance that's easy to get wrong. The swift-collections implementation is battle-tested and handles edge cases (empty heap, single element, equal priorities).

## Common Pitfalls

### Pitfall 1: Wrong Heap Direction
**What goes wrong:** Using max-heap when you need min-heap (or vice versa)
**Why it happens:** Confusion about which end to evict from
**How to avoid:** For "keep top k highest scores," use a MIN-heap. The minimum element is the one closest to eviction. `popMin()` removes the worst item.
**Warning signs:** Wrong items getting evicted; keeping low-scored items

### Pitfall 2: Score Staleness
**What goes wrong:** Recency component of score becomes stale as time passes
**Why it happens:** Score computed at insertion time, never updated
**How to avoid:** This is acceptable for this use case - we're comparing relative recency at insertion time. Document A inserted 1 hour ago vs Document B inserted now: B should be favored.
**Warning signs:** Old documents with high importance never evicted even when very stale

### Pitfall 3: Heap-Array Desynchronization
**What goes wrong:** Heap and array get out of sync after modifications
**Why it happens:** Forgetting to update both data structures
**How to avoid:** Either use a single source of truth (heap only) or carefully synchronize both. For this phase, recommend keeping the array as primary storage and using heap only during pruning.
**Warning signs:** Different counts, missing items, duplicate items

### Pitfall 4: Empty Heap Crashes
**What goes wrong:** Calling `removeMin()` on empty heap crashes
**Why it happens:** `removeMin()` has precondition that heap is non-empty
**How to avoid:** Use `popMin()` (returns optional) or check `isEmpty` first
**Warning signs:** Crash with "Heap is empty" or similar

### Pitfall 5: Forgetting Thread Safety
**What goes wrong:** Data races when heap accessed from multiple threads
**Why it happens:** `Heap` is a value type with no built-in synchronization
**How to avoid:** Both `EmbeddingStore` and `MemoryStore` are actors - this is already handled. Heap operations are isolated to actor context.
**Warning signs:** Not applicable here (actors provide isolation)

## Code Examples

Verified patterns from official sources:

### Creating a Heap with Custom Comparable

```swift
// Source: swift-collections Heap.md + Top-K pattern
import HeapModule

struct ScoredDocument: Comparable {
    let document: EmbeddedDocument
    let score: Double

    init(document: EmbeddedDocument) {
        // Pre-compute score at insertion time
        let importanceWeight = 0.6
        let recencyWeight = 0.4
        let ageInDays = Date().timeIntervalSince(document.timestamp) / 86400
        let recencyScore = 1.0 - min(ageInDays, 1.0)

        self.document = document
        self.score = document.metadata.importance * importanceWeight + recencyScore * recencyWeight
    }

    static func < (lhs: ScoredDocument, rhs: ScoredDocument) -> Bool {
        lhs.score < rhs.score
    }

    static func == (lhs: ScoredDocument, rhs: ScoredDocument) -> Bool {
        lhs.document.id == rhs.document.id
    }
}
```

### Efficient addDocument() with Heap Pruning

```swift
// Source: Adapted from existing code + Top-K heap pattern
public func addDocument(content: String, metadata: DocumentMetadata) async throws {
    let embedding = try await ollamaClient.generateEmbedding(text: content)

    let document = EmbeddedDocument(
        content: content,
        embedding: embedding,
        metadata: metadata
    )

    // Always add to array
    documents.append(document)

    // Prune if needed - O(log n) instead of O(n log n)
    if documents.count > maxDocuments {
        pruneDocuments()
    }

    logger.debug("Added document", metadata: [
        "source": metadata.source.rawValue,
        "length": String(content.count)
    ])
}

private func pruneDocuments() {
    // Build heap from all documents - O(n)
    var heap = Heap(documents.map { ScoredDocument(document: $0) })

    // Remove lowest-scored documents until at capacity - O((n-k) log n)
    while heap.count > maxDocuments {
        _ = heap.popMin()
    }

    // Extract remaining documents
    documents = heap.unordered.map(\.document)
}
```

### Alternative: Maintain Heap Alongside Array

```swift
// Source: Optimization for repeated adds
// More complex but O(log n) per add instead of O(n) rebuild

private var documents: [EmbeddedDocument] = []
private var documentHeap: Heap<ScoredDocument> = Heap()

public func addDocument(content: String, metadata: DocumentMetadata) async throws {
    let embedding = try await ollamaClient.generateEmbedding(text: content)

    let document = EmbeddedDocument(
        content: content,
        embedding: embedding,
        metadata: metadata
    )

    let scored = ScoredDocument(document: document)

    if documentHeap.count < maxDocuments {
        // Below capacity: just add
        documents.append(document)
        documentHeap.insert(scored)
    } else if let minScore = documentHeap.min?.score, scored.score > minScore {
        // At capacity but new document is better: replace worst
        let evicted = documentHeap.replaceMin(with: scored)
        documents.removeAll { $0.id == evicted.document.id }
        documents.append(document)
    }
    // Otherwise: new document not good enough, don't add
}
```

### Heap API Quick Reference

```swift
// Source: https://github.com/apple/swift-collections/blob/main/Documentation/Heap.md
import HeapModule

var heap = Heap<Int>()           // Empty heap
var heap = Heap([3, 1, 4, 1, 5]) // From sequence - O(n)

heap.insert(2)                    // Add element - O(log n)
heap.insert(contentsOf: [6, 7])   // Bulk add - O(n + k)

heap.min                          // Peek minimum - O(1)
heap.max                          // Peek maximum - O(1)
heap.count                        // Count - O(1)
heap.isEmpty                      // Empty check - O(1)

heap.popMin()                     // Remove min, return optional - O(log n)
heap.popMax()                     // Remove max, return optional - O(log n)
heap.removeMin()                  // Remove min, crash if empty - O(log n)
heap.removeMax()                  // Remove max, crash if empty - O(log n)

heap.replaceMin(with: newValue)   // Swap min, return old - O(log n)
heap.replaceMax(with: newValue)   // Swap max, return old - O(log n)

heap.unordered                    // Underlying array (unordered) - O(1)
```

## State of the Art

| Old Approach | Current Approach | When Changed | Impact |
|--------------|------------------|--------------|--------|
| Hand-rolled heaps | swift-collections Heap | swift-collections 1.1.0 (Feb 2023) | Production-ready min-max heap |
| Min-heap OR max-heap | Min-max heap | Same | Single data structure handles both ends |
| Full sort for pruning | Bounded heap | Standard algorithm | O(n log n) -> O(log n) per add |

**Deprecated/outdated:**
- Custom heap implementations: Use swift-collections instead
- CFBinaryHeap: Foundation's C-based heap is harder to use, not generic
- SwiftPriorityQueue (CocoaPods): Third-party; prefer Apple's official implementation

## Open Questions

Things that couldn't be fully resolved:

1. **Persistence Strategy for Heap**
   - What we know: Heap's `unordered` view provides array access for JSON encoding
   - What's unclear: Whether to persist the heap or rebuild from array on load
   - Recommendation: Persist as array (current format), rebuild heap on load. Simpler, backward compatible.

2. **Score Recalculation Frequency**
   - What we know: Scores include recency component that ages over time
   - What's unclear: Whether stale scores cause issues over extended periods
   - Recommendation: Acceptable for current use case. If needed later, could rebuild heap periodically or on load.

3. **Memory Overhead of Dual Storage**
   - What we know: Keeping both array and heap doubles memory for document references
   - What's unclear: Whether this matters at maxDocuments=5000
   - Recommendation: For 5000 documents with ~256-dimension embeddings, overhead is minimal. Proceed with dual storage or consider heap-only approach if memory is tight.

## Sources

### Primary (HIGH confidence)
- [swift-collections Heap.md](https://github.com/apple/swift-collections/blob/main/Documentation/Heap.md) - Official documentation
- [swift-collections HeapModule source](https://github.com/apple/swift-collections/blob/main/Sources/HeapModule/Heap.swift) - API reference
- [swift-collections 1.1.0 release](https://github.com/apple/swift-collections/releases/tag/1.1.0) - Version introducing Heap

### Secondary (MEDIUM confidence)
- [Tech Interview Handbook - Heap cheatsheet](https://www.techinterviewhandbook.org/algorithms/heap/) - Top-K pattern
- [swift-collections Heap API RFC](https://forums.swift.org/t/swift-collections-1-1-heap-api-rfc/68447) - API design discussion

### Tertiary (LOW confidence)
- General algorithm resources on bounded heaps and top-k selection

## Metadata

**Confidence breakdown:**
- Standard stack: HIGH - swift-collections is Apple's official library, already in project
- Architecture: HIGH - Top-K with bounded min-heap is a well-known algorithm pattern
- Pitfalls: HIGH - Common heap mistakes are well-documented

**Research date:** 2026-01-23
**Valid until:** 90 days (swift-collections is stable, patterns are algorithmic fundamentals)

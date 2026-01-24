# Phase 4: Statistics Optimization - Context

**Gathered:** 2026-01-24
**Status:** Ready for planning

<domain>
## Phase Boundary

Make getStatistics() O(1) instead of O(n) by maintaining running counters. Additionally, expand statistics to include LLM-specific observability metrics (semantic match rate, miss reasons) inspired by LangFuse patterns.

**Scope extended:** User requested LLM observability metrics beyond the original O(1) optimization goal.

</domain>

<decisions>
## Implementation Decisions

### Age bucket granularity
- Keep current buckets: < 1h, < 1d, < 7d, > 7d
- No need for finer or coarser granularity

### Bucket drift handling
- Lazy recalculation: recalculate on getStatistics() calls when stale
- Maximum recalculation frequency: every 5 minutes
- Cache a "last calculated" timestamp to throttle O(n) recalcs

### Counter update timing
- Synchronous updates on every add/remove operation
- Counters always reflect current state after mutations
- Hit count (totalHits) included in optimized statistics

### Semantic match tracking
- Track exactHits vs semanticHits for cache hit breakdown
- This enables measuring the value of semantic cache matching from Phase 3

### Cache miss reasons
- Detailed breakdown including: no_match, expired, below_threshold, no_embedding, empty_cache, query_too_short, etc.
- Useful for understanding and debugging cache behavior

### Query type tracking
- Track at handler level (EnhancedRequestHandler), not cache level
- Separation of concerns: cache handles caching, handler handles request-type awareness

### Claude's Discretion
- Pruned vs invalidated removal tracking (if useful for observability)
- Structure of CacheStatistics vs separate CacheMetrics
- Exact miss reason categories based on debugging needs
- Implementation of 5-minute recalculation throttle

</decisions>

<specifics>
## Specific Ideas

- "LangFuse-style observability" — user is interested in AI/LLM metrics patterns
- Want visibility into semantic matching effectiveness post Phase 3
- Detailed miss reasons valuable for understanding cache behavior

</specifics>

<deferred>
## Deferred Ideas

None — discussion stayed within extended scope (O(1) optimization + LLM observability)

</deferred>

---

*Phase: 04-statistics-optimization*
*Context gathered: 2026-01-24*

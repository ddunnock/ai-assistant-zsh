// Sources/AIShellCore/Cache/ResponseCache.swift

import Foundation
import Crypto

/// Cached response entry
public struct CachedResponse: Codable {
    public let key: String
    public let response: String
    public let timestamp: Date
    public let hitCount: Int
    public let metadata: [String: String]
    public let embedding: [Double]?
    public let originalQuery: String?

    public init(
        key: String,
        response: String,
        timestamp: Date = Date(),
        hitCount: Int = 0,
        metadata: [String: String] = [:],
        embedding: [Double]? = nil,
        originalQuery: String? = nil
    ) {
        self.key = key
        self.response = response
        self.timestamp = timestamp
        self.hitCount = hitCount
        self.metadata = metadata
        self.embedding = embedding
        self.originalQuery = originalQuery
    }
}

/// Response cache for reducing duplicate LLM calls
public actor ResponseCache {
    private var cache: [String: CachedResponse] = [:]
    private let storageURL: URL?
    private let logger = LoggerFactory.create(category: "cache")

    // Configuration
    private let maxCacheSize = 500
    private let maxAge: TimeInterval = 86400 * 7  // 7 days
    private let enablePersistence: Bool

    // Semantic cache configuration
    private let semanticThreshold: Double
    private let ollamaClient: OllamaClient?
    private let enableSemanticCache: Bool

    // Statistics counters
    private struct CacheCounters {
        var totalEntries: Int = 0
        var totalHits: Int = 0
        var exactHits: Int = 0
        var semanticHits: Int = 0
        var ageBuckets: [String: Int] = ["< 1h": 0, "< 1d": 0, "< 7d": 0, "> 7d": 0]
        var missReasons: [String: Int] = [:]
        var lastRecalculated: Date = Date()
    }

    private var counters: CacheCounters = CacheCounters()
    private let recalcInterval: TimeInterval = 300  // 5 minutes

    public init(
        storageURL: URL?,
        enablePersistence: Bool = true,
        semanticThreshold: Double = 0.92,
        ollamaClient: OllamaClient? = nil,
        enableSemanticCache: Bool = true
    ) {
        self.storageURL = storageURL
        self.enablePersistence = enablePersistence
        self.semanticThreshold = semanticThreshold
        self.ollamaClient = ollamaClient
        self.enableSemanticCache = enableSemanticCache
    }

    // MARK: - Cache Operations

    /// Get cached response if available and fresh
    /// - Parameters:
    ///   - key: The cache key to look up
    ///   - query: Optional query text for semantic matching (fallback if exact match fails)
    /// - Returns: Cached response if found (exact or semantic match), nil otherwise
    public func get(_ key: String, query: String? = nil) async -> String? {
        // Level 1: Exact match lookup (fast path)
        if let entry = cache[key] {
            // Check if expired
            if isExpired(entry) {
                cache.removeValue(forKey: key)
                counters.totalEntries -= 1
                counters.missReasons["expired", default: 0] += 1
                let ageHours = Date().timeIntervalSince(entry.timestamp) / 3600
                logger.info("Cache entry expired and removed", metadata: [
                    "key": String(key.prefix(16)) + "...",
                    "age_hours": String(format: "%.1f", ageHours),
                    "max_age_hours": String(format: "%.1f", maxAge / 3600)
                ])
            } else {
                // Increment hit count
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
                counters.totalHits += 1
                counters.exactHits += 1

                logger.debug("Cache hit (exact)", metadata: [
                    "key": key,
                    "hit_count": String(updated.hitCount)
                ])

                return entry.response
            }
        }

        // Level 2: Semantic match lookup (if enabled and query provided)
        if enableSemanticCache,
           let query = query,
           ollamaClient != nil {
            if let semanticResult = await findSimilarMatch(query: query) {
                counters.totalHits += 1
                counters.semanticHits += 1
                return semanticResult
            }
        }

        // Miss tracking - after both paths fail
        if cache.isEmpty {
            counters.missReasons["empty_cache", default: 0] += 1
        } else if query == nil {
            counters.missReasons["no_embedding", default: 0] += 1
        } else {
            counters.missReasons["no_match", default: 0] += 1
        }

        return nil
    }

    /// Find a semantically similar cached response
    /// - Parameter query: The query text to match against cached embeddings
    /// - Returns: The cached response if similarity >= threshold, nil otherwise
    private func findSimilarMatch(query: String) async -> String? {
        guard let client = ollamaClient else { return nil }

        // Generate embedding for the query
        let queryEmbedding: [Double]
        do {
            queryEmbedding = try await client.generateEmbedding(text: query)
        } catch {
            logger.warning("Failed to generate embedding for semantic cache lookup", metadata: [
                "error": String(describing: error)
            ])
            return nil
        }

        // Scan all non-expired cache entries with embeddings
        var bestMatch: (entry: CachedResponse, similarity: Double)?

        for entry in cache.values {
            // Skip expired entries
            guard !isExpired(entry) else { continue }

            // Skip entries without embeddings
            guard let entryEmbedding = entry.embedding else { continue }

            // Calculate similarity
            let similarity = cosineSimilarity(queryEmbedding, entryEmbedding)

            // Track best match
            if similarity >= semanticThreshold {
                if bestMatch == nil || similarity > bestMatch!.similarity {
                    bestMatch = (entry, similarity)
                }
            }
        }

        // Return best match if found
        if let match = bestMatch {
            // Increment hit count for the matched entry
            let updated = CachedResponse(
                key: match.entry.key,
                response: match.entry.response,
                timestamp: match.entry.timestamp,
                hitCount: match.entry.hitCount + 1,
                metadata: match.entry.metadata,
                embedding: match.entry.embedding,
                originalQuery: match.entry.originalQuery
            )
            cache[match.entry.key] = updated

            logger.info("Cache hit (semantic)", metadata: [
                "similarity": String(format: "%.3f", match.similarity),
                "threshold": String(format: "%.2f", semanticThreshold),
                "original_query": match.entry.originalQuery ?? "unknown",
                "hit_count": String(updated.hitCount)
            ])

            return match.entry.response
        }

        return nil
    }

    /// Check if a cache entry is expired
    private func isExpired(_ entry: CachedResponse) -> Bool {
        return Date().timeIntervalSince(entry.timestamp) > maxAge
    }

    /// Get age bucket key for a given age
    private func ageBucket(for age: TimeInterval) -> String {
        if age < 3600 {
            return "< 1h"
        } else if age < 86400 {
            return "< 1d"
        } else if age < 604800 {
            return "< 7d"
        } else {
            return "> 7d"
        }
    }

    /// Calculate cosine similarity between two vectors
    private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count else { return 0.0 }

        let dotProduct = zip(a, b).map(*).reduce(0, +)
        let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
        let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

        guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }

        return dotProduct / (magnitudeA * magnitudeB)
    }

    /// Set cache entry with optional embedding generation for semantic matching
    /// - Parameters:
    ///   - key: The cache key
    ///   - response: The response to cache
    ///   - query: Optional query text for embedding generation (enables semantic matching)
    ///   - metadata: Additional metadata to store with the entry
    public func set(
        _ key: String,
        response: String,
        query: String? = nil,
        metadata: [String: String] = [:]
    ) async {
        var embedding: [Double]? = nil

        // Generate embedding if semantic cache is enabled and query is provided
        if enableSemanticCache,
           let query = query,
           let client = ollamaClient {
            do {
                embedding = try await client.generateEmbedding(text: query)
                logger.debug("Generated embedding for cache entry", metadata: [
                    "key": String(key.prefix(16)) + "...",
                    "embedding_dim": String(embedding?.count ?? 0)
                ])
            } catch {
                logger.warning("Failed to generate embedding for cache entry", metadata: [
                    "error": String(describing: error)
                ])
                // Continue without embedding - entry will still be cached for exact match
            }
        }

        // Check if this is a new entry
        let isNewEntry = cache[key] == nil

        let entry = CachedResponse(
            key: key,
            response: response,
            metadata: metadata,
            embedding: embedding,
            originalQuery: query
        )

        cache[key] = entry

        // Update counters for new entry
        if isNewEntry {
            counters.totalEntries += 1
            counters.ageBuckets["< 1h", default: 0] += 1
        }

        // Prune if needed
        if cache.count > maxCacheSize {
            pruneCache()
        }

        logger.debug("Cache set", metadata: [
            "key": key,
            "has_embedding": String(embedding != nil)
        ])
    }

    /// Create cache key from request components using JSON serialization for collision resistance
    public func createKey(type: String, content: String, context: [String: String] = [:]) -> String {
        // Use JSON-based key generation for collision-resistant hashing
        struct CacheKeyComponents: Encodable {
            let type: String
            let content: String
            let context: [String: String]
        }

        let components = CacheKeyComponents(type: type, content: content, context: context)

        // Serialize to JSON with sorted keys for deterministic output
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys

        do {
            let jsonData = try encoder.encode(components)
            let hash = SHA256.hash(data: jsonData)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            // Fallback to pipe-delimited format if JSON encoding fails (defensive)
            logger.warning("JSON encoding failed for cache key, using fallback", metadata: [
                "error": String(describing: error)
            ])
            var fallbackComponents = [type, content]
            for key in context.keys.sorted() {
                if let value = context[key], !value.isEmpty {
                    fallbackComponents.append("\(key):\(value)")
                }
            }
            let combined = fallbackComponents.joined(separator: "|")
            let data = Data(combined.utf8)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        }
    }

    /// Invalidate cache entry
    public func invalidate(_ key: String) {
        if cache.removeValue(forKey: key) != nil {
            counters.totalEntries -= 1
        }
        logger.debug("Cache invalidated", metadata: ["key": key])
    }

    /// Clear all cache
    public func clear() {
        cache.removeAll()
        counters = CacheCounters()
        logger.info("Cache cleared")
    }

    /// Get cache statistics
    public func getStatistics() -> CacheStatistics {
        let totalEntries = cache.count
        let totalHits = cache.values.reduce(0) { $0 + $1.hitCount }

        var ageDistribution: [String: Int] = [
            "< 1h": 0,
            "< 1d": 0,
            "< 7d": 0,
            "> 7d": 0
        ]

        let now = Date()
        for entry in cache.values {
            let age = now.timeIntervalSince(entry.timestamp)

            if age < 3600 {
                ageDistribution["< 1h"]! += 1
            } else if age < 86400 {
                ageDistribution["< 1d"]! += 1
            } else if age < 86400 * 7 {
                ageDistribution["< 7d"]! += 1
            } else {
                ageDistribution["> 7d"]! += 1
            }
        }

        return CacheStatistics(
            totalEntries: totalEntries,
            totalHits: totalHits,
            ageDistribution: ageDistribution
        )
    }

    // MARK: - Cache Management

    private func pruneCache() {
        let before = cache.count

        // Sort by score (hitCount * recency)
        let sorted = cache.values.sorted { entry1, entry2 in
            let score1 = calculateScore(entry1)
            let score2 = calculateScore(entry2)
            return score1 > score2
        }

        // Keep top entries
        let toKeep = sorted.prefix(maxCacheSize)
        cache = Dictionary(uniqueKeysWithValues: toKeep.map { ($0.key, $0) })

        let removed = before - cache.count
        counters.totalEntries -= removed

        logger.debug("Pruned cache", metadata: [
            "kept": String(cache.count)
        ])
    }

    private func calculateScore(_ entry: CachedResponse) -> Double {
        let hitWeight = 0.6
        let recencyWeight = 0.4

        let hitScore = Double(entry.hitCount)
        let recencyScore = 1.0 - min(Date().timeIntervalSince(entry.timestamp) / maxAge, 1.0)

        return hitScore * hitWeight + recencyScore * recencyWeight * 10
    }

    // MARK: - Persistence

    /// Save cache to disk
    public func save() async throws {
        guard enablePersistence, let storageURL = storageURL else { return }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let entries = Array(cache.values)
        let encoded = try encoder.encode(entries)

        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try encoded.write(to: storageURL)

        logger.info("Saved cache to disk", metadata: [
            "path": storageURL.path,
            "entry_count": String(cache.count)
        ])
    }

    /// Load cache from disk
    public func load() async throws {
        guard enablePersistence, let storageURL = storageURL else { return }
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("No existing cache found")
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let entries = try decoder.decode([CachedResponse].self, from: data)

        // Filter out expired entries
        let fresh = entries.filter { entry in
            Date().timeIntervalSince(entry.timestamp) <= maxAge
        }

        cache = Dictionary(uniqueKeysWithValues: fresh.map { ($0.key, $0) })

        logger.info("Loaded cache from disk", metadata: [
            "path": storageURL.path,
            "entry_count": String(cache.count)
        ])
    }

    /// Clean expired entries
    public func cleanExpired() {
        let before = cache.count

        cache = cache.filter { _, entry in
            Date().timeIntervalSince(entry.timestamp) <= maxAge
        }

        let removed = before - cache.count

        if removed > 0 {
            logger.info("Cleaned expired entries", metadata: [
                "removed": String(removed)
            ])
        }
    }
}

// MARK: - Supporting Types

public struct CacheStatistics {
    public let totalEntries: Int
    public let totalHits: Int
    public let exactHits: Int
    public let semanticHits: Int
    public let ageDistribution: [String: Int]
    public let missReasons: [String: Int]

    public init(
        totalEntries: Int,
        totalHits: Int,
        ageDistribution: [String: Int],
        exactHits: Int = 0,
        semanticHits: Int = 0,
        missReasons: [String: Int] = [:]
    ) {
        self.totalEntries = totalEntries
        self.totalHits = totalHits
        self.exactHits = exactHits
        self.semanticHits = semanticHits
        self.ageDistribution = ageDistribution
        self.missReasons = missReasons
    }

    public var hitRate: Double {
        let totalRequests = totalHits + missReasons.values.reduce(0, +)
        return totalRequests > 0 ? Double(totalHits) / Double(totalRequests) : 0.0
    }

    public var semanticHitRate: Double {
        return totalHits > 0 ? Double(semanticHits) / Double(totalHits) : 0.0
    }
}

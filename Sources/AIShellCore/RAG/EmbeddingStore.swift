// Sources/AIShellCore/RAG/EmbeddingStore.swift

import Foundation
import Crypto
import OrderedCollections
import HeapModule

/// A document with its embedding
public struct EmbeddedDocument: Codable, Identifiable {
    public let id: UUID
    public let content: String
    public let embedding: [Double]
    public let metadata: DocumentMetadata
    public let timestamp: Date

    public init(
        id: UUID = UUID(),
        content: String,
        embedding: [Double],
        metadata: DocumentMetadata,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.content = content
        self.embedding = embedding
        self.metadata = metadata
        self.timestamp = timestamp
    }
}

/// Metadata for a document
public struct DocumentMetadata: Codable {
    public let source: DocumentSource
    public let title: String?
    public let tags: [String]
    public let workingDirectory: String?
    public let importance: Double

    public init(
        source: DocumentSource,
        title: String? = nil,
        tags: [String] = [],
        workingDirectory: String? = nil,
        importance: Double = 0.5
    ) {
        self.source = source
        self.title = title
        self.tags = tags
        self.workingDirectory = workingDirectory
        self.importance = importance
    }
}

/// Document source types
public enum DocumentSource: String, Codable {
    case manPage        // Man page documentation
    case readme         // README files
    case helpText       // Command --help output
    case commandExample // Example commands
    case projectDocs    // Project-specific documentation
    case userNote       // User-created notes
    case conversation   // Past conversations
}

/// Search result with similarity score
public struct SearchResult {
    public let document: EmbeddedDocument
    public let similarity: Double

    public init(document: EmbeddedDocument, similarity: Double) {
        self.document = document
        self.similarity = similarity
    }
}

/// Vector store for RAG (Retrieval-Augmented Generation)
public actor EmbeddingStore {
    private let storageURL: URL
    private let ollamaClient: OllamaClient
    private let logger = LoggerFactory.create(category: "rag")

    private var documents: [EmbeddedDocument] = []
    private let maxDocuments = 5000

    // Query embedding cache (LRU)
    private var embeddingCache: OrderedDictionary<String, [Double]> = [:]
    private let maxCacheSize: Int
    private var cacheHits: Int = 0
    private var cacheMisses: Int = 0

    public init(storageURL: URL, ollamaClient: OllamaClient, maxCacheSize: Int = 1000) {
        self.storageURL = storageURL
        self.ollamaClient = ollamaClient
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Document Management

    /// Add a document with embedding
    public func addDocument(
        content: String,
        metadata: DocumentMetadata
    ) async throws {
        let embedding = try await ollamaClient.generateEmbedding(text: content)

        let document = EmbeddedDocument(
            content: content,
            embedding: embedding,
            metadata: metadata
        )

        documents.append(document)

        // Prune if needed using heap-based selection
        if documents.count > maxDocuments {
            pruneDocuments()
        }

        logger.debug("Added document", metadata: [
            "source": metadata.source.rawValue,
            "length": String(content.count)
        ])
    }

    // MARK: - Embedding Cache

    /// Create cache key from query text using SHA256 hash
    private func createCacheKey(for query: String) -> String {
        let data = Data(query.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// Get cached embedding, moving it to end (MRU position)
    private func getCachedEmbedding(for key: String) -> [Double]? {
        guard let value = embeddingCache.removeValue(forKey: key) else {
            return nil
        }
        embeddingCache[key] = value  // Re-insert at end (most recently used)
        return value
    }

    /// Cache embedding, evicting oldest if at capacity
    private func setCachedEmbedding(_ embedding: [Double], for key: String) {
        while embeddingCache.count >= maxCacheSize {
            embeddingCache.removeFirst()  // Evict oldest (LRU)
        }
        embeddingCache[key] = embedding
    }

    /// Get embedding cache statistics
    public func getCacheStatistics() -> EmbeddingCacheStatistics {
        return EmbeddingCacheStatistics(
            totalEntries: embeddingCache.count,
            cacheHits: cacheHits,
            cacheMisses: cacheMisses
        )
    }

    /// Clear the embedding cache
    public func clearCache() {
        embeddingCache.removeAll()
        cacheHits = 0
        cacheMisses = 0
        logger.info("Embedding cache cleared")
    }

    // MARK: - Pruning

    /// Prune documents to maxDocuments using heap-based top-k selection
    private func pruneDocuments() {
        // Build min-heap from all documents
        var heap = Heap(documents.map { ScoredDocument(document: $0) })

        // Remove lowest-scored documents until at capacity
        while heap.count > maxDocuments {
            _ = heap.popMin()
        }

        // Extract remaining documents (highest scored)
        documents = heap.unordered.map(\.document)
    }

    /// Search documents by semantic similarity
    public func search(
        query: String,
        limit: Int = 5,
        minSimilarity: Double = 0.5,
        source: DocumentSource? = nil,
        workingDirectory: String? = nil
    ) async throws -> [SearchResult] {
        // Generate cache key
        let cacheKey = createCacheKey(for: query)

        // Check cache first
        let queryEmbedding: [Double]
        if let cached = getCachedEmbedding(for: cacheKey) {
            cacheHits += 1
            queryEmbedding = cached
            logger.debug("Embedding cache hit", metadata: ["key": String(cacheKey.prefix(16)) + "..."])
        } else {
            cacheMisses += 1
            queryEmbedding = try await ollamaClient.generateEmbedding(text: query)
            setCachedEmbedding(queryEmbedding, for: cacheKey)
            logger.debug("Embedding cache miss", metadata: ["key": String(cacheKey.prefix(16)) + "..."])
        }

        var candidates = documents

        // Filter by source if specified
        if let source = source {
            candidates = candidates.filter { $0.metadata.source == source }
        }

        // Filter by working directory if specified
        if let workingDirectory = workingDirectory {
            candidates = candidates.filter { $0.metadata.workingDirectory == workingDirectory }
        }

        // Calculate similarities
        let results = candidates.map { document in
            let similarity = cosineSimilarity(queryEmbedding, document.embedding)
            return SearchResult(document: document, similarity: similarity)
        }

        // Filter and sort by similarity
        return Array(results
            .filter { $0.similarity >= minSimilarity }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit))
    }

    /// Get relevant context for a command
    public func getRelevantContext(
        command: String,
        workingDirectory: String?,
        limit: Int = 3
    ) async throws -> [EmbeddedDocument] {
        let results = try await search(
            query: command,
            limit: limit,
            minSimilarity: 0.6,
            workingDirectory: workingDirectory
        )

        return results.map { $0.document }
    }

    // MARK: - Indexing Helpers

    /// Index man page
    public func indexManPage(
        command: String,
        content: String,
        importance: Double = 0.8
    ) async throws {
        let metadata = DocumentMetadata(
            source: .manPage,
            title: "man \(command)",
            tags: ["documentation", command],
            importance: importance
        )

        try await addDocument(content: content, metadata: metadata)
    }

    /// Index README file
    public func indexReadme(
        path: String,
        content: String,
        workingDirectory: String,
        importance: Double = 0.9
    ) async throws {
        let metadata = DocumentMetadata(
            source: .readme,
            title: path,
            tags: ["documentation", "readme"],
            workingDirectory: workingDirectory,
            importance: importance
        )

        try await addDocument(content: content, metadata: metadata)
    }

    /// Index command example
    public func indexCommandExample(
        command: String,
        description: String,
        workingDirectory: String? = nil,
        importance: Double = 0.7
    ) async throws {
        let content = """
        Command: \(command)
        Description: \(description)
        """

        let metadata = DocumentMetadata(
            source: .commandExample,
            title: command,
            tags: ["example"],
            workingDirectory: workingDirectory,
            importance: importance
        )

        try await addDocument(content: content, metadata: metadata)
    }

    /// Index help text
    public func indexHelpText(
        command: String,
        helpText: String,
        importance: Double = 0.7
    ) async throws {
        let metadata = DocumentMetadata(
            source: .helpText,
            title: "\(command) --help",
            tags: ["help", command],
            importance: importance
        )

        try await addDocument(content: helpText, metadata: metadata)
    }

    // MARK: - Batch Operations

    /// Index directory of markdown files
    public func indexDirectory(
        url: URL,
        workingDirectory: String,
        recursive: Bool = true
    ) async throws {
        let fileManager = FileManager.default

        var urls: [URL] = []

        if recursive {
            guard let enumerator = fileManager.enumerator(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { return }

            // Collect all URLs first to avoid async iteration warning
            let allObjects = enumerator.allObjects
            for case let fileURL as URL in allObjects {
                if fileURL.pathExtension == "md" {
                    urls.append(fileURL)
                }
            }
        } else {
            urls = try fileManager.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: [.isRegularFileKey]
            ).filter { $0.pathExtension == "md" }
        }

        logger.info("Indexing directory", metadata: [
            "path": url.path,
            "file_count": String(urls.count)
        ])

        for fileURL in urls {
            do {
                let content = try String(contentsOf: fileURL, encoding: .utf8)

                let metadata = DocumentMetadata(
                    source: .projectDocs,
                    title: fileURL.lastPathComponent,
                    tags: ["documentation"],
                    workingDirectory: workingDirectory,
                    importance: 0.8
                )

                try await addDocument(content: content, metadata: metadata)
            } catch {
                logger.warning("Failed to index file", metadata: [
                    "path": fileURL.path,
                    "error": String(describing: error)
                ])
            }
        }
    }

    // MARK: - Persistence

    /// Save embeddings to disk
    public func save() async throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let encoded = try encoder.encode(documents)

        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try encoded.write(to: storageURL)

        logger.info("Saved embeddings to disk", metadata: [
            "path": storageURL.path,
            "document_count": String(documents.count)
        ])
    }

    /// Load embeddings from disk
    public func load() async throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("No existing embedding store found")
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        documents = try decoder.decode([EmbeddedDocument].self, from: data)

        logger.info("Loaded embeddings from disk", metadata: [
            "path": storageURL.path,
            "document_count": String(documents.count)
        ])
    }

    /// Get statistics
    public func getStatistics() -> [String: Any] {
        var sourceCount: [String: Int] = [:]

        for doc in documents {
            let source = doc.metadata.source.rawValue
            sourceCount[source, default: 0] += 1
        }

        return [
            "total_documents": documents.count,
            "by_source": sourceCount
        ]
    }
}

// MARK: - Vector Math

/// Calculate cosine similarity between two vectors
private func cosineSimilarity(_ a: [Double], _ b: [Double]) -> Double {
    guard a.count == b.count else { return 0.0 }

    let dotProduct = zip(a, b).map(*).reduce(0, +)
    let magnitudeA = sqrt(a.map { $0 * $0 }.reduce(0, +))
    let magnitudeB = sqrt(b.map { $0 * $0 }.reduce(0, +))

    guard magnitudeA > 0 && magnitudeB > 0 else { return 0.0 }

    return dotProduct / (magnitudeA * magnitudeB)
}

// MARK: - Cache Statistics

public struct EmbeddingCacheStatistics {
    public let totalEntries: Int
    public let cacheHits: Int
    public let cacheMisses: Int

    public var hitRatio: Double {
        let total = cacheHits + cacheMisses
        return total > 0 ? Double(cacheHits) / Double(total) : 0.0
    }

    public init(totalEntries: Int, cacheHits: Int, cacheMisses: Int) {
        self.totalEntries = totalEntries
        self.cacheHits = cacheHits
        self.cacheMisses = cacheMisses
    }
}

// MARK: - Heap-Based Pruning Support

/// Wrapper for heap-based document pruning
struct ScoredDocument: Comparable {
    let document: EmbeddedDocument
    let score: Double

    init(document: EmbeddedDocument) {
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

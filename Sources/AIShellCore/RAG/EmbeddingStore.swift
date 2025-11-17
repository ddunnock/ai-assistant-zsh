// Sources/AIShellCore/RAG/EmbeddingStore.swift

import Foundation

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

    public init(storageURL: URL, ollamaClient: OllamaClient) {
        self.storageURL = storageURL
        self.ollamaClient = ollamaClient
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

        // Prune if needed
        if documents.count > maxDocuments {
            documents = documents.sorted { doc1, doc2 in
                // Sort by importance and recency
                let importanceWeight = 0.6
                let recencyWeight = 0.4

                let score1 = doc1.metadata.importance * importanceWeight +
                    (1.0 - min(Date().timeIntervalSince(doc1.timestamp) / 86400, 1.0)) * recencyWeight
                let score2 = doc2.metadata.importance * importanceWeight +
                    (1.0 - min(Date().timeIntervalSince(doc2.timestamp) / 86400, 1.0)) * recencyWeight

                return score1 > score2
            }.prefix(maxDocuments).map { $0 }
        }

        logger.debug("Added document", metadata: [
            "source": metadata.source.rawValue,
            "length": String(content.count)
        ])
    }

    /// Search documents by semantic similarity
    public func search(
        query: String,
        limit: Int = 5,
        minSimilarity: Double = 0.5,
        source: DocumentSource? = nil,
        workingDirectory: String? = nil
    ) async throws -> [SearchResult] {
        let queryEmbedding = try await ollamaClient.generateEmbedding(text: query)

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
        return results
            .filter { $0.similarity >= minSimilarity }
            .sorted { $0.similarity > $1.similarity }
            .prefix(limit)
            .map { $0 }
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

            for case let fileURL as URL in enumerator {
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

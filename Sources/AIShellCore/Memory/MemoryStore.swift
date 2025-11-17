// Sources/AIShellCore/Memory/MemoryStore.swift

import Foundation

/// Memory types
public enum MemoryType: String, Codable {
    case session        // Current session context
    case longTerm       // Persistent facts and preferences
    case command        // Command history with context
    case project        // Project-specific information
}

/// A memory entry
public struct MemoryEntry: Codable, Identifiable {
    public let id: UUID
    public let type: MemoryType
    public let content: String
    public let metadata: [String: String]
    public let timestamp: Date
    public let workingDirectory: String?
    public let importance: Double  // 0.0 to 1.0

    public init(
        id: UUID = UUID(),
        type: MemoryType,
        content: String,
        metadata: [String: String] = [:],
        timestamp: Date = Date(),
        workingDirectory: String? = nil,
        importance: Double = 0.5
    ) {
        self.id = id
        self.type = type
        self.content = content
        self.metadata = metadata
        self.timestamp = timestamp
        self.workingDirectory = workingDirectory
        self.importance = importance
    }
}

/// Session context for conversation continuity
public struct SessionContext: Codable {
    public var sessionId: String
    public var startTime: Date
    public var lastActivity: Date
    public var conversationHistory: [ConversationTurn]
    public var workingDirectory: String?
    public var gitBranch: String?
    public var activeProject: String?

    public init(
        sessionId: String = UUID().uuidString,
        startTime: Date = Date(),
        workingDirectory: String? = nil,
        gitBranch: String? = nil,
        activeProject: String? = nil
    ) {
        self.sessionId = sessionId
        self.startTime = startTime
        self.lastActivity = startTime
        self.conversationHistory = []
        self.workingDirectory = workingDirectory
        self.gitBranch = gitBranch
        self.activeProject = activeProject
    }
}

/// A single conversation turn
public struct ConversationTurn: Codable {
    public let timestamp: Date
    public let userMessage: String
    public let assistantResponse: String
    public let requestType: String
    public let metadata: [String: String]

    public init(
        timestamp: Date = Date(),
        userMessage: String,
        assistantResponse: String,
        requestType: String,
        metadata: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.userMessage = userMessage
        self.assistantResponse = assistantResponse
        self.requestType = requestType
        self.metadata = metadata
    }
}

/// Memory store for managing different types of memory
public actor MemoryStore {
    private let storageURL: URL
    private let logger = LoggerFactory.create(category: "memory")

    private var memories: [MemoryType: [MemoryEntry]] = [:]
    private var sessions: [String: SessionContext] = [:]
    private var currentSessionId: String?

    // Configuration
    private let maxSessionAge: TimeInterval = 3600  // 1 hour
    private let maxMemoriesPerType = 1000
    private let maxConversationHistory = 50

    public init(storageURL: URL) {
        self.storageURL = storageURL
    }

    // MARK: - Session Management

    /// Start or resume a session
    public func startSession(
        workingDirectory: String?,
        gitBranch: String?,
        activeProject: String?
    ) -> String {
        // Check if we can resume existing session
        if let sessionId = currentSessionId,
           let session = sessions[sessionId],
           Date().timeIntervalSince(session.lastActivity) < maxSessionAge {
            // Resume existing session
            var updatedSession = session
            updatedSession.lastActivity = Date()
            updatedSession.workingDirectory = workingDirectory
            updatedSession.gitBranch = gitBranch
            updatedSession.activeProject = activeProject
            sessions[sessionId] = updatedSession

            logger.info("Resumed session", metadata: ["session_id": sessionId])
            return sessionId
        }

        // Create new session
        let session = SessionContext(
            workingDirectory: workingDirectory,
            gitBranch: gitBranch,
            activeProject: activeProject
        )
        currentSessionId = session.sessionId
        sessions[session.sessionId] = session

        logger.info("Started new session", metadata: ["session_id": session.sessionId])
        return session.sessionId
    }

    /// Get current session
    public func getCurrentSession() -> SessionContext? {
        guard let sessionId = currentSessionId else { return nil }
        return sessions[sessionId]
    }

    /// Add conversation turn to session
    public func addConversationTurn(
        sessionId: String,
        userMessage: String,
        assistantResponse: String,
        requestType: String,
        metadata: [String: String] = [:]
    ) {
        guard var session = sessions[sessionId] else { return }

        let turn = ConversationTurn(
            userMessage: userMessage,
            assistantResponse: assistantResponse,
            requestType: requestType,
            metadata: metadata
        )

        session.conversationHistory.append(turn)
        session.lastActivity = Date()

        // Keep only recent history
        if session.conversationHistory.count > maxConversationHistory {
            session.conversationHistory = Array(session.conversationHistory.suffix(maxConversationHistory))
        }

        sessions[sessionId] = session

        logger.debug("Added conversation turn", metadata: [
            "session_id": sessionId,
            "type": requestType
        ])
    }

    /// Get recent conversation history
    public func getRecentConversation(sessionId: String, limit: Int = 10) -> [ConversationTurn] {
        guard let session = sessions[sessionId] else { return [] }
        return Array(session.conversationHistory.suffix(limit))
    }

    // MARK: - Memory Management

    /// Add a memory entry
    public func addMemory(_ entry: MemoryEntry) {
        if memories[entry.type] == nil {
            memories[entry.type] = []
        }

        memories[entry.type]?.append(entry)

        // Prune old memories if needed
        if let count = memories[entry.type]?.count, count > maxMemoriesPerType {
            // Keep most important and recent memories
            memories[entry.type] = memories[entry.type]?.sorted { entry1, entry2 in
                // Sort by importance and recency
                let importanceWeight = 0.7
                let recencyWeight = 0.3

                let score1 = entry1.importance * importanceWeight +
                    (1.0 - min(Date().timeIntervalSince(entry1.timestamp) / 86400, 1.0)) * recencyWeight
                let score2 = entry2.importance * importanceWeight +
                    (1.0 - min(Date().timeIntervalSince(entry2.timestamp) / 86400, 1.0)) * recencyWeight

                return score1 > score2
            }.prefix(maxMemoriesPerType).map { $0 }
        }

        logger.debug("Added memory", metadata: [
            "type": entry.type.rawValue,
            "importance": String(entry.importance)
        ])
    }

    /// Retrieve memories by type
    public func getMemories(type: MemoryType, limit: Int? = nil) -> [MemoryEntry] {
        guard let typeMemories = memories[type] else { return [] }

        let sorted = typeMemories.sorted { $0.timestamp > $1.timestamp }

        if let limit = limit {
            return Array(sorted.prefix(limit))
        }

        return sorted
    }

    /// Search memories by content
    public func searchMemories(query: String, limit: Int = 10) -> [MemoryEntry] {
        let allMemories = memories.values.flatMap { $0 }
        let queryLower = query.lowercased()

        return allMemories
            .filter { $0.content.lowercased().contains(queryLower) }
            .sorted { $0.importance > $1.importance }
            .prefix(limit)
            .map { $0 }
    }

    /// Get project-specific memories
    public func getProjectMemories(projectPath: String, limit: Int = 20) -> [MemoryEntry] {
        guard let projectMemories = memories[.project] else { return [] }

        return projectMemories
            .filter { $0.workingDirectory == projectPath }
            .sorted { $0.timestamp > $1.timestamp }
            .prefix(limit)
            .map { $0 }
    }

    /// Learn from command execution
    public func learnCommand(
        command: String,
        workingDirectory: String?,
        success: Bool,
        output: String? = nil,
        context: [String: String] = [:]
    ) {
        var metadata = context
        metadata["success"] = String(success)
        if let output = output {
            metadata["output_preview"] = String(output.prefix(200))
        }

        let importance = success ? 0.6 : 0.8  // Failed commands are more important to remember

        let entry = MemoryEntry(
            type: .command,
            content: command,
            metadata: metadata,
            workingDirectory: workingDirectory,
            importance: importance
        )

        addMemory(entry)
    }

    /// Store a fact for long-term memory
    public func storeFact(
        content: String,
        metadata: [String: String] = [:],
        importance: Double = 0.7
    ) {
        let entry = MemoryEntry(
            type: .longTerm,
            content: content,
            metadata: metadata,
            importance: importance
        )

        addMemory(entry)
    }

    // MARK: - Persistence

    /// Save memories to disk
    public func save() async throws {
        let data = MemorySnapshot(
            memories: memories,
            sessions: sessions,
            currentSessionId: currentSessionId
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let encoded = try encoder.encode(data)

        try FileManager.default.createDirectory(
            at: storageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        try encoded.write(to: storageURL)

        logger.info("Saved memories to disk", metadata: [
            "path": storageURL.path
        ])
    }

    /// Load memories from disk
    public func load() async throws {
        guard FileManager.default.fileExists(atPath: storageURL.path) else {
            logger.info("No existing memory store found")
            return
        }

        let data = try Data(contentsOf: storageURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(MemorySnapshot.self, from: data)

        memories = snapshot.memories
        sessions = snapshot.sessions
        currentSessionId = snapshot.currentSessionId

        logger.info("Loaded memories from disk", metadata: [
            "path": storageURL.path,
            "session_count": String(sessions.count)
        ])
    }

    /// Clear old sessions
    public func pruneOldSessions() {
        let cutoff = Date().addingTimeInterval(-maxSessionAge * 24)  // Keep 24x session age

        sessions = sessions.filter { _, session in
            session.lastActivity > cutoff
        }

        logger.debug("Pruned old sessions")
    }
}

// MARK: - Supporting Types

private struct MemorySnapshot: Codable {
    let memories: [MemoryType: [MemoryEntry]]
    let sessions: [String: SessionContext]
    let currentSessionId: String?
}

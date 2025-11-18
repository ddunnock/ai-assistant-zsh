// Sources/AIShellCore/Models/Request.swift

import Foundation

/// Request sent from ZSH to daemon
public struct Request: Codable, Sendable {
    public let id: String
    public let type: RequestType
    public let payload: Payload
    public let timestamp: Date
    
    public init(
        id: String = UUID().uuidString,
        type: RequestType,
        payload: Payload,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.type = type
        self.payload = payload
        self.timestamp = timestamp
    }
    
    public enum RequestType: String, Codable, Sendable {
        case suggest        // Inline suggestion
        case explain        // Explain command
        case task           // Natural language task
        case health         // Health check
        case autocomplete   // Automatic code completion

        // Phase 2: Memory management
        case remember       // Store a fact in long-term memory
        case forget         // Remove from memory
        case recall         // Query memory

        // Phase 2: RAG operations
        case index          // Index documentation/files
        case search         // Search indexed documents
    }
    
    public struct Payload: Codable, Sendable {
        public let command: String?
        public let workingDirectory: String?
        public let task: String?
        public let context: ContextInfo?

        // Phase 2 fields
        public let fact: String?            // For remember
        public let query: String?           // For recall/search
        public let filePath: String?        // For index
        public let content: String?         // For index
        public let importance: Double?      // For remember
        public let tags: [String]?          // For remember/index

        public init(
            command: String? = nil,
            workingDirectory: String? = nil,
            task: String? = nil,
            context: ContextInfo? = nil,
            fact: String? = nil,
            query: String? = nil,
            filePath: String? = nil,
            content: String? = nil,
            importance: Double? = nil,
            tags: [String]? = nil
        ) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.task = task
            self.context = context
            self.fact = fact
            self.query = query
            self.filePath = filePath
            self.content = content
            self.importance = importance
            self.tags = tags
        }
    }
    
    public struct ContextInfo: Codable, Sendable {
        public let history: [String]?
        public let environment: [String: String]?
        public let gitBranch: String?
        
        public init(
            history: [String]? = nil,
            environment: [String: String]? = nil,
            gitBranch: String? = nil
        ) {
            self.history = history
            self.environment = environment
            self.gitBranch = gitBranch
        }
    }
}

// MARK: - Convenience Initializers

extension Request {
    public static func suggest(command: String, workingDirectory: String) -> Request {
        Request(
            type: .suggest,
            payload: Payload(
                command: command,
                workingDirectory: workingDirectory
            )
        )
    }
    
    public static func explain(command: String) -> Request {
        Request(
            type: .explain,
            payload: Payload(command: command)
        )
    }
    
    public static func task(description: String, workingDirectory: String) -> Request {
        Request(
            type: .task,
            payload: Payload(
                workingDirectory: workingDirectory,
                task: description
            )
        )
    }
    
    public static func health() -> Request {
        Request(
            type: .health,
            payload: Payload()
        )
    }

    // Phase 2 convenience initializers

    public static func remember(fact: String, importance: Double = 0.7, tags: [String] = []) -> Request {
        Request(
            type: .remember,
            payload: Payload(
                fact: fact,
                importance: importance,
                tags: tags
            )
        )
    }

    public static func recall(query: String) -> Request {
        Request(
            type: .recall,
            payload: Payload(query: query)
        )
    }

    public static func index(filePath: String, content: String, workingDirectory: String) -> Request {
        Request(
            type: .index,
            payload: Payload(
                workingDirectory: workingDirectory,
                filePath: filePath,
                content: content
            )
        )
    }

    public static func search(query: String) -> Request {
        Request(
            type: .search,
            payload: Payload(query: query)
        )
    }

    public static func autocomplete(partialCommand: String, workingDirectory: String, context: ContextInfo? = nil) -> Request {
        Request(
            type: .autocomplete,
            payload: Payload(
                command: partialCommand,
                workingDirectory: workingDirectory,
                context: context
            )
        )
    }
}
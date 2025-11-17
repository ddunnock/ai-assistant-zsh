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
    }
    
    public struct Payload: Codable, Sendable {
        public let command: String?
        public let workingDirectory: String?
        public let task: String?
        public let context: ContextInfo?
        
        public init(
            command: String? = nil,
            workingDirectory: String? = nil,
            task: String? = nil,
            context: ContextInfo? = nil
        ) {
            self.command = command
            self.workingDirectory = workingDirectory
            self.task = task
            self.context = context
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
}
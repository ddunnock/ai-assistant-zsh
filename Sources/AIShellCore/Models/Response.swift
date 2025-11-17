// Sources/AIShellCore/Models/Response.swift

import Foundation

/// Response sent from daemon to ZSH
public struct Response: Codable, Sendable {
    public let id: String
    public let requestId: String
    public let status: Status
    public let payload: Payload
    public let timestamp: Date
    public let processingTime: TimeInterval?
    
    public init(
        id: String = UUID().uuidString,
        requestId: String,
        status: Status,
        payload: Payload,
        timestamp: Date = Date(),
        processingTime: TimeInterval? = nil
    ) {
        self.id = id
        self.requestId = requestId
        self.status = status
        self.payload = payload
        self.timestamp = timestamp
        self.processingTime = processingTime
    }
    
    public enum Status: String, Codable, Sendable {
        case success
        case error
        case partial
    }
    
    public struct Payload: Codable, Sendable {
        public let suggestion: String?
        public let explanation: String?
        public let commands: [String]?
        public let error: ErrorInfo?
        public let metadata: [String: String]?
        
        public init(
            suggestion: String? = nil,
            explanation: String? = nil,
            commands: [String]? = nil,
            error: ErrorInfo? = nil,
            metadata: [String: String]? = nil
        ) {
            self.suggestion = suggestion
            self.explanation = explanation
            self.commands = commands
            self.error = error
            self.metadata = metadata
        }
    }
    
    public struct ErrorInfo: Codable, Sendable {
        public let code: String
        public let message: String
        public let details: String?
        
        public init(code: String, message: String, details: String? = nil) {
            self.code = code
            self.message = message
            self.details = details
        }
    }
}

// MARK: - Convenience Initializers

extension Response {
    public static func success(
        requestId: String,
        suggestion: String? = nil,
        explanation: String? = nil,
        commands: [String]? = nil,
        processingTime: TimeInterval? = nil
    ) -> Response {
        Response(
            requestId: requestId,
            status: .success,
            payload: Payload(
                suggestion: suggestion,
                explanation: explanation,
                commands: commands
            ),
            processingTime: processingTime
        )
    }
    
    public static func error(
        requestId: String,
        code: String,
        message: String,
        details: String? = nil
    ) -> Response {
        Response(
            requestId: requestId,
            status: .error,
            payload: Payload(
                error: ErrorInfo(
                    code: code,
                    message: message,
                    details: details
                )
            )
        )
    }
}
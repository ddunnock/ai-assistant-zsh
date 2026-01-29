// Sources/AIShellCore/Clients/ZaiModels.swift

import Foundation

// MARK: - Request Types

/// Chat request for z.ai OpenAI-compatible API
public struct ZaiChatRequest: Codable {
    public let model: String
    public let messages: [ZaiChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?
    public let topP: Double?
    public let stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case temperature
        case maxTokens = "max_tokens"
        case topP = "top_p"
        case stream
    }

    public init(
        model: String,
        messages: [ZaiChatMessage],
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        topP: Double? = nil,
        stream: Bool = false
    ) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
        self.stream = stream
    }
}

/// Chat message for z.ai API
public struct ZaiChatMessage: Codable {
    public let role: String
    public let content: String

    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }

    /// Create a system message
    public static func system(_ content: String) -> ZaiChatMessage {
        ZaiChatMessage(role: "system", content: content)
    }

    /// Create a user message
    public static func user(_ content: String) -> ZaiChatMessage {
        ZaiChatMessage(role: "user", content: content)
    }

    /// Create an assistant message
    public static func assistant(_ content: String) -> ZaiChatMessage {
        ZaiChatMessage(role: "assistant", content: content)
    }
}

/// Options for z.ai generation
public struct ZaiOptions {
    public let temperature: Double
    public let maxTokens: Int?
    public let topP: Double?

    public static let `default` = ZaiOptions(
        temperature: 0.7,
        maxTokens: nil,
        topP: nil
    )

    public init(
        temperature: Double = 0.7,
        maxTokens: Int? = nil,
        topP: Double? = nil
    ) {
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.topP = topP
    }
}

// MARK: - Response Types

/// Chat completion response from z.ai API
public struct ZaiChatResponse: Codable {
    public let id: String
    public let object: String
    public let created: Int
    public let model: String
    public let choices: [ZaiChoice]
    public let usage: ZaiUsage?

    /// Get the content of the first choice's message
    public var content: String {
        choices.first?.message.content ?? ""
    }
}

/// Choice in z.ai response
public struct ZaiChoice: Codable {
    public let index: Int
    public let message: ZaiChatMessage
    public let finishReason: String?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }
}

/// Token usage information
public struct ZaiUsage: Codable {
    public let promptTokens: Int
    public let completionTokens: Int
    public let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Error Response

/// Error response from z.ai API
public struct ZaiErrorResponse: Codable {
    public let error: ZaiErrorDetail
}

/// Error detail from z.ai API
public struct ZaiErrorDetail: Codable {
    public let message: String
    public let type: String?
    public let code: String?
}

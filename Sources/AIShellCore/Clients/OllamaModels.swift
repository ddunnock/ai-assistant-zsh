// Sources/AIShellCore/Clients/OllamaModels.swift

import Foundation

// MARK: - Generate Request/Response

public struct OllamaGenerateRequest: Codable {
    let model: String
    let prompt: String
    let system: String?
    let stream: Bool
    let options: OllamaOptions?
    
    public init(
        model: String,
        prompt: String,
        system: String? = nil,
        stream: Bool = false,
        options: OllamaOptions? = nil
    ) {
        self.model = model
        self.prompt = prompt
        self.system = system
        self.stream = stream
        self.options = options
    }
}

public struct OllamaGenerateResponse: Codable {
    let model: String
    let createdAt: String
    let response: String
    let done: Bool
    let context: [Int]?
    let totalDuration: Int64?
    let loadDuration: Int64?
    let promptEvalCount: Int?
    let promptEvalDuration: Int64?
    let evalCount: Int?
    let evalDuration: Int64?
    
    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case response
        case done
        case context
        case totalDuration = "total_duration"
        case loadDuration = "load_duration"
        case promptEvalCount = "prompt_eval_count"
        case promptEvalDuration = "prompt_eval_duration"
        case evalCount = "eval_count"
        case evalDuration = "eval_duration"
    }
    
    public var tokensPerSecond: Double? {
        guard let evalCount = evalCount,
              let evalDuration = evalDuration,
              evalDuration > 0 else {
            return nil
        }
        return Double(evalCount) / (Double(evalDuration) / 1_000_000_000.0)
    }
}

// MARK: - Chat Request/Response

public struct OllamaChatRequest: Codable {
    let model: String
    let messages: [OllamaChatMessage]
    let stream: Bool
    let options: OllamaOptions?
    
    public init(
        model: String,
        messages: [OllamaChatMessage],
        stream: Bool = false,
        options: OllamaOptions? = nil
    ) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.options = options
    }
}

public struct OllamaChatResponse: Codable {
    let model: String
    let createdAt: String
    let message: OllamaChatMessage
    let done: Bool
    
    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case message
        case done
    }
}

public struct OllamaChatMessage: Codable {
    let role: String
    let content: String
    
    public init(role: String, content: String) {
        self.role = role
        self.content = content
    }
    
    public static func system(_ content: String) -> OllamaChatMessage {
        OllamaChatMessage(role: "system", content: content)
    }
    
    public static func user(_ content: String) -> OllamaChatMessage {
        OllamaChatMessage(role: "user", content: content)
    }
    
    public static func assistant(_ content: String) -> OllamaChatMessage {
        OllamaChatMessage(role: "assistant", content: content)
    }
}

// MARK: - Options

public struct OllamaOptions: Codable {
    let temperature: Double?
    let numCtx: Int?
    let topP: Double?
    let topK: Int?
    
    enum CodingKeys: String, CodingKey {
        case temperature
        case numCtx = "num_ctx"
        case topP = "top_p"
        case topK = "top_k"
    }
    
    public init(
        temperature: Double? = nil,
        numCtx: Int? = nil,
        topP: Double? = nil,
        topK: Int? = nil
    ) {
        self.temperature = temperature
        self.numCtx = numCtx
        self.topP = topP
        self.topK = topK
    }
    
    public static let `default` = OllamaOptions(
        temperature: 0.7,
        numCtx: 4096
    )
}

// MARK: - List Models

public struct OllamaListResponse: Codable {
    let models: [OllamaModelInfo]
}

public struct OllamaModelInfo: Codable {
    let name: String
    let modifiedAt: String
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case name
        case modifiedAt = "modified_at"
        case size
    }
}

// MARK: - Embeddings

public struct OllamaEmbeddingRequest: Codable {
    let model: String
    let prompt: String

    public init(model: String, prompt: String) {
        self.model = model
        self.prompt = prompt
    }
}

public struct OllamaEmbeddingResponse: Codable {
    let embedding: [Double]

    public init(embedding: [Double]) {
        self.embedding = embedding
    }
}

// MARK: - Streaming

/// Callback for streaming responses
public typealias StreamCallback = (String) -> Void

/// Stream chunk for generate/chat endpoints
public struct OllamaStreamChunk: Codable {
    let model: String
    let createdAt: String
    let response: String?
    let message: OllamaChatMessage?
    let done: Bool

    enum CodingKeys: String, CodingKey {
        case model
        case createdAt = "created_at"
        case response
        case message
        case done
    }
}
// Sources/AIShellCore/Clients/OllamaClient.swift

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

/// Client for communicating with Ollama API
public actor OllamaClient {
    private let baseURL: String
    private let httpClient: HTTPClient
    private let logger = LoggerFactory.create(category: "ollama")
    private let model: String
    private let options: OllamaOptions
    
    public init(
        baseURL: String = "http://localhost:11434",
        model: String = "llama3.1:8b",
        options: OllamaOptions = .default
    ) {
        self.baseURL = baseURL
        self.model = model
        self.options = options
        
        var configuration = HTTPClient.Configuration()
        configuration.timeout = .init(
            connect: .seconds(5),
            read: .seconds(30)
        )
        self.httpClient = HTTPClient(
            eventLoopGroupProvider: .singleton,
            configuration: configuration
        )
    }
    
    deinit {
        try? httpClient.syncShutdown()
    }
    
    // MARK: - Public API
    
    /// Generate text completion
    public func generate(
        prompt: String,
        system: String? = nil
    ) async throws -> String {
        let startTime = Date()
        
        let requestBody = OllamaGenerateRequest(
            model: model,
            prompt: prompt,
            system: system,
            stream: false,
            options: options
        )
        
        logger.debug("Generating completion", metadata: [
            "model": model,
            "prompt_length": String(prompt.count)
        ])
        
        let response = try await post(
            endpoint: "/api/generate",
            body: requestBody,
            responseType: OllamaGenerateResponse.self
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        logger.info("Generation complete", metadata: [
            "duration": duration.milliseconds,
            "response_length": String(response.response.count),
            "tokens_per_sec": response.tokensPerSecond.map { String(format: "%.1f", $0) } ?? "N/A"
        ])
        
        return response.response
    }
    
    /// Chat completion (multi-turn)
    public func chat(messages: [OllamaChatMessage]) async throws -> String {
        let startTime = Date()
        
        let requestBody = OllamaChatRequest(
            model: model,
            messages: messages,
            stream: false,
            options: options
        )
        
        logger.debug("Chat request", metadata: [
            "model": model,
            "message_count": String(messages.count)
        ])
        
        let response = try await post(
            endpoint: "/api/chat",
            body: requestBody,
            responseType: OllamaChatResponse.self
        )
        
        let duration = Date().timeIntervalSince(startTime)
        
        logger.info("Chat complete", metadata: [
            "duration": duration.milliseconds,
            "response_length": String(response.message.content.count)
        ])
        
        return response.message.content
    }
    
    /// List available models
    public func listModels() async throws -> [OllamaModelInfo] {
        logger.debug("Listing models")
        
        let response = try await get(
            endpoint: "/api/tags",
            responseType: OllamaListResponse.self
        )
        
        logger.info("Listed \(response.models.count) models")
        
        return response.models
    }
    
    /// Health check
    public func healthCheck() async -> Bool {
        do {
            _ = try await listModels()
            return true
        } catch {
            logger.error("Health check failed", error: error)
            return false
        }
    }
    
    // MARK: - Private Helpers
    
    private func post<T: Encodable, R: Decodable>(
        endpoint: String,
        body: T,
        responseType: R.Type
    ) async throws -> R {
        let url = baseURL + endpoint
        
        var request = HTTPClientRequest(url: url)
        request.method = .POST
        request.headers.add(name: "Content-Type", value: "application/json")
        
        let bodyData = try JSONEncoder().encode(body)
        request.body = .bytes(ByteBuffer(data: bodyData))
        
        let response = try await httpClient.execute(request, timeout: .seconds(60))
        
        guard response.status == .ok else {
            throw AIShellError.ollamaError(
                "HTTP \(response.status.code): \(response.status.reasonPhrase)"
            )
        }
        
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024) // 10MB
        guard let responseData = responseBody.toData() else {
            throw AIShellError.ollamaError("Failed to read response body")
        }
        
        return try JSONDecoder().decode(R.self, from: responseData)
    }
    
    private func get<R: Decodable>(
        endpoint: String,
        responseType: R.Type
    ) async throws -> R {
        let url = baseURL + endpoint
        
        var request = HTTPClientRequest(url: url)
        request.method = .GET
        
        let response = try await httpClient.execute(request, timeout: .seconds(10))
        
        guard response.status == .ok else {
            throw AIShellError.ollamaError(
                "HTTP \(response.status.code): \(response.status.reasonPhrase)"
            )
        }
        
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024)
        guard let responseData = responseBody.toData() else {
            throw AIShellError.ollamaError("Failed to read response body")
        }
        
        return try JSONDecoder().decode(R.self, from: responseData)
    }
}
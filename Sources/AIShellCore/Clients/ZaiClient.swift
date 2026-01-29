// Sources/AIShellCore/Clients/ZaiClient.swift

import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1

/// Client for communicating with z.ai OpenAI-compatible API
public actor ZaiClient {
    private let baseURL: String
    private let httpClient: HTTPClient
    private let logger = LoggerFactory.create(category: "zai")
    private let model: String
    private let apiKey: String
    private let options: ZaiOptions

    public init(
        baseURL: String = "https://api.z.ai/api/paas/v4",
        model: String = "glm-4.7",
        apiKey: String,
        options: ZaiOptions = .default
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.options = options

        var configuration = HTTPClient.Configuration()
        // Longer timeouts for cloud API
        configuration.timeout = .init(
            connect: .seconds(10),
            read: .seconds(60)
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

    /// Generate text completion (converts to chat format)
    public func generate(
        prompt: String,
        system: String? = nil
    ) async throws -> String {
        var messages: [ZaiChatMessage] = []

        if let system = system, !system.isEmpty {
            messages.append(.system(system))
        }
        messages.append(.user(prompt))

        return try await chat(messages: messages)
    }

    /// Chat completion with messages
    public func chat(messages: [ZaiChatMessage]) async throws -> String {
        let startTime = Date()

        let requestBody = ZaiChatRequest(
            model: model,
            messages: messages,
            temperature: options.temperature,
            maxTokens: options.maxTokens,
            topP: options.topP,
            stream: false
        )

        logger.debug("Chat request", metadata: [
            "model": model,
            "message_count": String(messages.count)
        ])

        let response = try await post(
            endpoint: "/chat/completions",
            body: requestBody,
            responseType: ZaiChatResponse.self
        )

        let duration = Date().timeIntervalSince(startTime)
        let content = response.content

        logger.info("Chat complete", metadata: [
            "duration": duration.milliseconds,
            "response_length": String(content.count),
            "total_tokens": response.usage.map { String($0.totalTokens) } ?? "N/A"
        ])

        return content
    }

    /// Health check - verify API connectivity
    public func healthCheck() async -> Bool {
        do {
            // Send a minimal request to verify connectivity
            let testMessages = [ZaiChatMessage.user("ping")]
            let requestBody = ZaiChatRequest(
                model: model,
                messages: testMessages,
                maxTokens: 1,
                stream: false
            )

            _ = try await post(
                endpoint: "/chat/completions",
                body: requestBody,
                responseType: ZaiChatResponse.self
            )
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
        request.headers.add(name: "Authorization", value: "Bearer \(apiKey)")

        let bodyData = try JSONEncoder().encode(body)
        request.body = .bytes(ByteBuffer(data: bodyData))

        let response = try await httpClient.execute(request, timeout: .seconds(90))

        // Read response body
        let responseBody = try await response.body.collect(upTo: 10 * 1024 * 1024) // 10MB
        guard let responseData = responseBody.toData() else {
            throw AIShellError.zaiError("Failed to read response body")
        }

        // Check for errors
        guard response.status == .ok else {
            // Try to parse error response
            if let errorResponse = try? JSONDecoder().decode(ZaiErrorResponse.self, from: responseData) {
                throw AIShellError.zaiError(errorResponse.error.message)
            }
            throw AIShellError.zaiError(
                "HTTP \(response.status.code): \(response.status.reasonPhrase)"
            )
        }

        return try JSONDecoder().decode(R.self, from: responseData)
    }
}

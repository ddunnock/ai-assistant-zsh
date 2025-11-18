// Sources/AIShellCore/Server/RequestHandler.swift

import Foundation

/// Handles incoming requests and generates responses
public actor RequestHandler {
    private let ollamaClient: OllamaClient
    private let logger = LoggerFactory.create(category: "handler")
    
    public init(ollamaClient: OllamaClient) {
        self.ollamaClient = ollamaClient
    }
    
    /// Handle a request and return a response
    public func handle(_ request: Request) async -> Response {
        let startTime = Date()
        
        logger.info("Handling request", metadata: [
            "id": request.id,
            "type": request.type.rawValue
        ])
        
        do {
            let response = try await processRequest(request)
            let processingTime = Date().timeIntervalSince(startTime)
            
            logger.info("Request completed", metadata: [
                "id": request.id,
                "processing_time": processingTime.milliseconds,
                "status": response.status.rawValue
            ])
            
            return response
        } catch {
            logger.error("Request failed", error: error, metadata: [
                "id": request.id
            ])
            
            return errorResponse(for: request, error: error)
        }
    }
    
    // MARK: - Private Methods
    
    private func processRequest(_ request: Request) async throws -> Response {
        switch request.type {
        case .suggest:
            return try await handleSuggest(request)
        case .explain:
            return try await handleExplain(request)
        case .task:
            return try await handleTask(request)
        case .health:
            return await handleHealth(request)

        // Phase 2 features - not supported in basic handler
        case .remember, .forget, .recall, .index, .search:
            return Response.error(
                requestId: request.id,
                code: "FEATURE_NOT_SUPPORTED",
                message: "Phase 2 features require EnhancedRequestHandler"
            )
        }
    }
    
    private func handleSuggest(_ request: Request) async throws -> Response {
        guard let command = request.payload.command else {
            throw AIShellError.requestError("Missing command in suggest request")
        }
        
        let prompt = buildSuggestPrompt(
            command: command,
            context: request.payload.context
        )
        
        let suggestion = try await ollamaClient.generate(
            prompt: prompt,
            system: "You are a shell command assistant. Suggest completions or improvements for shell commands. Be concise and output only the suggested command without explanation."
        )
        
        return Response.success(
            requestId: request.id,
            suggestion: suggestion.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines),
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }
    
    private func handleExplain(_ request: Request) async throws -> Response {
        guard let command = request.payload.command else {
            throw AIShellError.requestError("Missing command in explain request")
        }
        
        let prompt = """
        Explain this shell command in clear, concise language:
        
        Command: \(command)
        
        Provide:
        1. What the command does
        2. What each option/flag means
        3. Any potential risks or side effects
        
        Keep the explanation under 200 words.
        """
        
        let explanation = try await ollamaClient.generate(
            prompt: prompt,
            system: "You are a shell command expert. Explain commands clearly and accurately."
        )
        
        return Response.success(
            requestId: request.id,
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }
    
    private func handleTask(_ request: Request) async throws -> Response {
        guard let task = request.payload.task else {
            throw AIShellError.requestError("Missing task description")
        }
        
        let prompt = """
        Convert this natural language task into shell commands:
        
        Task: \(task)
        Working Directory: \(request.payload.workingDirectory ?? "~")
        
        Output only the commands, one per line, with no explanation or markdown.
        """
        
        let commandsText = try await ollamaClient.generate(
            prompt: prompt,
            system: "You are a shell scripting expert. Convert tasks to safe, efficient shell commands."
        )

        // Clean up the response: remove markdown code blocks and empty lines
        let commands = commandsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { line in
                // Skip empty lines
                guard !line.isEmpty else { return false }
                // Skip markdown code blocks
                guard !line.hasPrefix("```") else { return false }
                // Skip comments
                guard !line.hasPrefix("#") else { return false }
                return true
            }

        return Response.success(
            requestId: request.id,
            commands: commands,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }
    
    private func handleHealth(_ request: Request) async -> Response {
        let isHealthy = await ollamaClient.healthCheck()
        
        if isHealthy {
            return Response.success(
                requestId: request.id,
                processingTime: Date().timeIntervalSince(request.timestamp)
            )
        } else {
            return Response.error(
                requestId: request.id,
                code: "OLLAMA_UNAVAILABLE",
                message: "Ollama service is not responding"
            )
        }
    }
    
    private func buildSuggestPrompt(command: String, context: Request.ContextInfo?) -> String {
        var prompt = "Current command: \(command)\n"
        
        if let history = context?.history, !history.isEmpty {
            prompt += "\nRecent commands:\n"
            prompt += history.suffix(5).joined(separator: "\n")
        }
        
        if let branch = context?.gitBranch {
            prompt += "\nGit branch: \(branch)"
        }
        
        prompt += "\n\nSuggest an improvement or completion for the current command."
        
        return prompt
    }
    
    private func errorResponse(for request: Request, error: Error) -> Response {
        let aiError = error as? AIShellError
        
        return Response.error(
            requestId: request.id,
            code: aiError?.errorCode ?? "UNKNOWN_ERROR",
            message: error.localizedDescription,
            details: String(describing: error)
        )
    }
}
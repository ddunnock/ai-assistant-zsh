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
        case .autocomplete:
            return try await handleAutocomplete(request)

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
    
    private func handleAutocomplete(_ request: Request) async throws -> Response {
        guard let partialCommand = request.payload.command else {
            throw AIShellError.requestError("Missing command in autocomplete request")
        }

        // Calculate base confidence score
        var confidence = calculateAutocompleteConfidence(for: partialCommand, context: request.payload.context)

        // If confidence is too low, don't bother calling AI
        guard confidence >= 0.3 else {
            return Response.success(
                requestId: request.id,
                completion: nil,
                confidence: 0.0,
                processingTime: Date().timeIntervalSince(request.timestamp)
            )
        }

        // Build contextual prompt
        let prompt = buildAutocompletePrompt(partialCommand: partialCommand, context: request.payload.context)

        // Get completion from AI
        let completion = try await ollamaClient.generate(
            prompt: prompt,
            system: "You are a shell autocomplete assistant. Complete the partial command with the most likely continuation. Output ONLY the completion text that should be added to the existing command, without repeating what's already typed. Keep it concise and on a single line."
        )

        let trimmedCompletion = completion.trimmingCharacters(in: .whitespacesAndNewlines)

        // Adjust confidence based on completion quality
        confidence = refineConfidence(
            baseConfidence: confidence,
            completion: trimmedCompletion,
            partialCommand: partialCommand
        )

        return Response.success(
            requestId: request.id,
            completion: trimmedCompletion,
            confidence: confidence,
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

    private func buildAutocompletePrompt(partialCommand: String, context: Request.ContextInfo?) -> String {
        var prompt = "Partial command: \(partialCommand)\n"

        if let history = context?.history, !history.isEmpty {
            prompt += "\nRecent commands:\n"
            prompt += history.suffix(3).joined(separator: "\n")
        }

        if let workingDir = context?.environment?["PWD"] {
            prompt += "\nWorking directory: \(workingDir)"
        }

        prompt += "\n\nComplete this command with the most likely continuation."

        return prompt
    }

    private func calculateAutocompleteConfidence(for command: String, context: Request.ContextInfo?) -> Double {
        var confidence: Double = 0.5 // Base confidence

        // Too short? Lower confidence
        if command.count < 3 {
            return 0.0
        }

        // Minimum length threshold
        if command.count < 10 {
            confidence *= 0.6
        }

        // Looks incomplete? Higher confidence
        let incompleMarkers = ["|", "&&", "||", ";", ">", "<", "$(", "\"", "'", " -", " --"]
        let endsWithIncomplete = incompleMarkers.contains { command.hasSuffix($0) } || command.hasSuffix(" ")

        if endsWithIncomplete {
            confidence *= 1.4
        }

        // Has context? Boost confidence
        if let history = context?.history, !history.isEmpty {
            confidence *= 1.1
        }

        // Common command patterns
        let commonCommands = ["git", "docker", "kubectl", "npm", "find", "grep", "awk", "sed"]
        if commonCommands.contains(where: { command.starts(with: $0 + " ") }) {
            confidence *= 1.2
        }

        // Clamp between 0 and 1
        return min(max(confidence, 0.0), 1.0)
    }

    private func refineConfidence(baseConfidence: Double, completion: String, partialCommand: String) -> Double {
        var confidence = baseConfidence

        // Empty completion? Zero confidence
        if completion.isEmpty {
            return 0.0
        }

        // Completion is too long or multi-line? Lower confidence
        if completion.count > 100 || completion.contains("\n") {
            confidence *= 0.5
        }

        // Completion repeats the partial command? Lower confidence
        if completion.lowercased().hasPrefix(partialCommand.lowercased()) {
            confidence *= 0.4
        }

        // Completion looks like explanation text? Lower confidence
        let explanationMarkers = ["This command", "This will", "You can", "To ", "Usage:"]
        if explanationMarkers.contains(where: { completion.starts(with: $0) }) {
            confidence *= 0.3
        }

        // Completion starts with common option patterns? Higher confidence
        if completion.starts(with: "-") || completion.starts(with: "/") || completion.starts(with: ".") {
            confidence *= 1.1
        }

        return min(max(confidence, 0.0), 1.0)
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
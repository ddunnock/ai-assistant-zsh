// Sources/AIShellCore/Server/EnhancedRequestHandler.swift

import Foundation

/// Enhanced request handler with Phase 2 features
public actor EnhancedRequestHandler {
    private let ollamaClient: OllamaClient
    private let memoryStore: MemoryStore?
    private let embeddingStore: EmbeddingStore?
    private let responseCache: ResponseCache?
    private let promptTemplates: PromptTemplates
    private let logger = LoggerFactory.create(category: "handler")

    private let enableMemory: Bool
    private let enableRAG: Bool
    private let enableCache: Bool

    public init(
        ollamaClient: OllamaClient,
        memoryStore: MemoryStore? = nil,
        embeddingStore: EmbeddingStore? = nil,
        responseCache: ResponseCache? = nil,
        promptTemplates: PromptTemplates,
        enableMemory: Bool = true,
        enableRAG: Bool = true,
        enableCache: Bool = true
    ) {
        self.ollamaClient = ollamaClient
        self.memoryStore = memoryStore
        self.embeddingStore = embeddingStore
        self.responseCache = responseCache
        self.promptTemplates = promptTemplates
        self.enableMemory = enableMemory
        self.enableRAG = enableRAG
        self.enableCache = enableCache
    }

    // MARK: - Request Handling

    /// Handle a request and return a response
    public func handle(_ request: Request) async -> Response {
        let startTime = Date()

        logger.info("Handling request", metadata: [
            "id": request.id,
            "type": request.type.rawValue
        ])

        do {
            // Start or resume session
            if enableMemory, let memoryStore = memoryStore {
                let sessionId = await memoryStore.startSession(
                    workingDirectory: request.payload.workingDirectory,
                    gitBranch: request.payload.context?.gitBranch,
                    activeProject: request.payload.workingDirectory
                )

                logger.debug("Session active", metadata: ["session_id": sessionId])
            }

            let response = try await processRequest(request)
            let processingTime = Date().timeIntervalSince(startTime)

            // Store conversation in memory
            if enableMemory,
               let memoryStore = memoryStore,
               let session = await memoryStore.getCurrentSession() {
                let userMessage = extractUserMessage(from: request)
                let assistantResponse = extractAssistantResponse(from: response)

                await memoryStore.addConversationTurn(
                    sessionId: session.sessionId,
                    userMessage: userMessage,
                    assistantResponse: assistantResponse,
                    requestType: request.type.rawValue
                )
            }

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

    // MARK: - Request Processing

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

        // Phase 2 handlers
        case .remember:
            return try await handleRemember(request)
        case .forget:
            return try await handleForget(request)
        case .recall:
            return try await handleRecall(request)
        case .index:
            return try await handleIndex(request)
        case .search:
            return try await handleSearch(request)
        }
    }

    // MARK: - Suggest Handler

    private func handleSuggest(_ request: Request) async throws -> Response {
        guard let command = request.payload.command else {
            throw AIShellError.requestError("Missing command in suggest request")
        }

        // Check cache first
        if enableCache, let cache = responseCache {
            let cacheKey = await cache.createKey(
                type: "suggest",
                content: command,
                context: ["workingDir": request.payload.workingDirectory ?? ""]
            )

            if let cached = await cache.get(cacheKey) {
                logger.debug("Cache hit for suggest", metadata: ["command": command])
                return Response.success(
                    requestId: request.id,
                    suggestion: cached,
                    processingTime: Date().timeIntervalSince(request.timestamp)
                )
            }
        }

        // Build prompt with context
        var variables = buildBaseVariables(for: request)
        variables["command"] = command

        // Add relevant context from RAG
        if enableRAG, let embeddingStore = embeddingStore {
            let relevantDocs = try await embeddingStore.getRelevantContext(
                command: command,
                workingDirectory: request.payload.workingDirectory,
                limit: 2
            )

            if !relevantDocs.isEmpty {
                let contextText = relevantDocs.map { $0.content }.joined(separator: "\n\n")
                variables["relevantContext"] = contextText
            }
        }

        // Get templates
        guard let systemTemplate = await promptTemplates.getTemplate("suggest_system"),
              let userTemplate = await promptTemplates.getTemplate("suggest_user") else {
            throw AIShellError.requestError("Prompt templates not found")
        }

        let systemPrompt = systemTemplate.system ?? ""
        let userPrompt = userTemplate.render(variables: variables)

        // Generate suggestion
        let suggestion = try await ollamaClient.generate(
            prompt: userPrompt,
            system: systemPrompt
        )

        let trimmedSuggestion = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cache the response
        if enableCache, let cache = responseCache {
            let cacheKey = await cache.createKey(
                type: "suggest",
                content: command,
                context: ["workingDir": request.payload.workingDirectory ?? ""]
            )

            await cache.set(cacheKey, response: trimmedSuggestion)
        }

        return Response.success(
            requestId: request.id,
            suggestion: trimmedSuggestion,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    // MARK: - Explain Handler

    private func handleExplain(_ request: Request) async throws -> Response {
        guard let command = request.payload.command else {
            throw AIShellError.requestError("Missing command in explain request")
        }

        // Check cache
        if enableCache, let cache = responseCache {
            let cacheKey = await cache.createKey(type: "explain", content: command)

            if let cached = await cache.get(cacheKey) {
                logger.debug("Cache hit for explain", metadata: ["command": command])
                return Response.success(
                    requestId: request.id,
                    explanation: cached,
                    processingTime: Date().timeIntervalSince(request.timestamp)
                )
            }
        }

        // Build prompt
        var variables = buildBaseVariables(for: request)
        variables["command"] = command

        // Add relevant documentation from RAG
        if enableRAG, let embeddingStore = embeddingStore {
            let relevantDocs = try await embeddingStore.search(
                query: command,
                limit: 1,
                minSimilarity: 0.7,
                source: .manPage
            )

            if !relevantDocs.isEmpty {
                let docContent = relevantDocs[0].document.content
                variables["relevantContext"] = String(docContent.prefix(500))
            }
        }

        guard let systemTemplate = await promptTemplates.getTemplate("explain_system"),
              let userTemplate = await promptTemplates.getTemplate("explain_user") else {
            throw AIShellError.requestError("Prompt templates not found")
        }

        let systemPrompt = systemTemplate.system ?? ""
        let userPrompt = userTemplate.render(variables: variables)

        let explanation = try await ollamaClient.generate(
            prompt: userPrompt,
            system: systemPrompt
        )

        let trimmedExplanation = explanation.trimmingCharacters(in: .whitespacesAndNewlines)

        // Cache the response
        if enableCache, let cache = responseCache {
            let cacheKey = await cache.createKey(type: "explain", content: command)
            await cache.set(cacheKey, response: trimmedExplanation)
        }

        return Response.success(
            requestId: request.id,
            explanation: trimmedExplanation,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    // MARK: - Task Handler

    private func handleTask(_ request: Request) async throws -> Response {
        guard let task = request.payload.task else {
            throw AIShellError.requestError("Missing task description")
        }

        // Build prompt with conversation history
        var variables = buildBaseVariables(for: request)
        variables["task"] = task
        variables["workingDirectory"] = request.payload.workingDirectory ?? "~"

        // Add conversation history from memory
        if enableMemory,
           let memoryStore = memoryStore,
           let session = await memoryStore.getCurrentSession() {
            let recentConversation = await memoryStore.getRecentConversation(
                sessionId: session.sessionId,
                limit: 3
            )

            if !recentConversation.isEmpty {
                let historyText = recentConversation.map { turn in
                    "User: \(turn.userMessage)\nAssistant: \(turn.assistantResponse)"
                }.joined(separator: "\n\n")

                variables["conversationHistory"] = historyText
            }
        }

        // Add relevant context from RAG
        if enableRAG, let embeddingStore = embeddingStore {
            let relevantDocs = try await embeddingStore.getRelevantContext(
                command: task,
                workingDirectory: request.payload.workingDirectory,
                limit: 2
            )

            if !relevantDocs.isEmpty {
                let contextText = relevantDocs.map { doc in
                    "Example: \(doc.content)"
                }.joined(separator: "\n")

                variables["relevantContext"] = contextText
            }
        }

        guard let systemTemplate = await promptTemplates.getTemplate("task_system"),
              let userTemplate = await promptTemplates.getTemplate("task_user") else {
            throw AIShellError.requestError("Prompt templates not found")
        }

        let systemPrompt = systemTemplate.system ?? ""
        let userPrompt = userTemplate.render(variables: variables)

        let commandsText = try await ollamaClient.generate(
            prompt: userPrompt,
            system: systemPrompt
        )

        let commands = commandsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }

        return Response.success(
            requestId: request.id,
            commands: commands,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    // MARK: - Health Handler

    private func handleHealth(_ request: Request) async -> Response {
        var healthInfo: [String: String] = [:]

        // Check Ollama
        let isOllamaHealthy = await ollamaClient.healthCheck()
        healthInfo["ollama"] = isOllamaHealthy ? "healthy" : "unhealthy"

        // Check components
        healthInfo["memory"] = enableMemory && memoryStore != nil ? "enabled" : "disabled"
        healthInfo["rag"] = enableRAG && embeddingStore != nil ? "enabled" : "disabled"
        healthInfo["cache"] = enableCache && responseCache != nil ? "enabled" : "disabled"

        // Get statistics if enabled
        if enableCache, let cache = responseCache {
            let stats = await cache.getStatistics()
            healthInfo["cache_entries"] = String(stats.totalEntries)
            healthInfo["cache_hits"] = String(stats.totalHits)
        }

        if enableRAG, let embeddingStore = embeddingStore {
            let stats = await embeddingStore.getStatistics()
            if let docCount = stats["total_documents"] as? Int {
                healthInfo["rag_documents"] = String(docCount)
            }
        }

        if isOllamaHealthy {
            return Response.success(
                requestId: request.id,
                metadata: healthInfo,
                processingTime: Date().timeIntervalSince(request.timestamp)
            )
        } else {
            return Response.error(
                requestId: request.id,
                code: "OLLAMA_UNAVAILABLE",
                message: "Ollama service is not responding",
                details: healthInfo.description
            )
        }
    }

    // MARK: - Helper Methods

    private func buildBaseVariables(for request: Request) -> [String: String] {
        var variables: [String: String] = [:]

        // Add command history
        if let history = request.payload.context?.history {
            let historyJSON = try? JSONEncoder().encode(history)
            if let historyString = historyJSON.flatMap({ String(data: $0, encoding: .utf8) }) {
                variables["history"] = historyString
            }
        }

        // Add context
        if let gitBranch = request.payload.context?.gitBranch {
            variables["gitBranch"] = gitBranch
        }

        if let workingDir = request.payload.workingDirectory {
            variables["workingDirectory"] = workingDir
        }

        return variables
    }

    private func extractUserMessage(from request: Request) -> String {
        if let command = request.payload.command {
            return command
        } else if let task = request.payload.task {
            return task
        }
        return request.type.rawValue
    }

    private func extractAssistantResponse(from response: Response) -> String {
        if let suggestion = response.payload.suggestion {
            return suggestion
        } else if let explanation = response.payload.explanation {
            return explanation
        } else if let commands = response.payload.commands {
            return commands.joined(separator: "\n")
        }
        return "OK"
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

    // MARK: - Phase 2 Handlers

    private func handleRemember(_ request: Request) async throws -> Response {
        guard let fact = request.payload.fact else {
            throw AIShellError.requestError("Missing fact to remember")
        }

        guard enableMemory, let memoryStore = memoryStore else {
            throw AIShellError.requestError("Memory is not enabled")
        }

        let importance = request.payload.importance ?? 0.7
        let tags = request.payload.tags ?? []

        var metadata: [String: String] = [:]
        for (index, tag) in tags.enumerated() {
            metadata["tag_\(index)"] = tag
        }

        await memoryStore.storeFact(
            content: fact,
            metadata: metadata,
            importance: importance
        )

        logger.info("Stored fact in memory", metadata: [
            "importance": String(importance)
        ])

        return Response.success(
            requestId: request.id,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    private func handleForget(_ request: Request) async throws -> Response {
        guard enableMemory, let memoryStore = memoryStore else {
            throw AIShellError.requestError("Memory is not enabled")
        }

        // For now, forget is not implemented - return success
        // In future, could implement selective memory deletion
        logger.info("Forget request received (not yet implemented)")

        return Response.success(
            requestId: request.id,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    private func handleRecall(_ request: Request) async throws -> Response {
        guard let query = request.payload.query else {
            throw AIShellError.requestError("Missing query for recall")
        }

        guard enableMemory, let memoryStore = memoryStore else {
            throw AIShellError.requestError("Memory is not enabled")
        }

        let memories = await memoryStore.searchMemories(query: query, limit: 5)

        let results = memories.map { memory in
            "[\(memory.type.rawValue)] \(memory.content)"
        }

        return Response.success(
            requestId: request.id,
            commands: results,  // Reuse commands field for results
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    private func handleIndex(_ request: Request) async throws -> Response {
        guard let filePath = request.payload.filePath,
              let content = request.payload.content else {
            throw AIShellError.requestError("Missing filePath or content for indexing")
        }

        guard enableRAG, let embeddingStore = embeddingStore else {
            throw AIShellError.requestError("RAG is not enabled")
        }

        let metadata = DocumentMetadata(
            source: .projectDocs,
            title: filePath,
            tags: request.payload.tags ?? [],
            workingDirectory: request.payload.workingDirectory,
            importance: request.payload.importance ?? 0.8
        )

        try await embeddingStore.addDocument(content: content, metadata: metadata)

        logger.info("Indexed document", metadata: [
            "path": filePath
        ])

        return Response.success(
            requestId: request.id,
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }

    private func handleSearch(_ request: Request) async throws -> Response {
        guard let query = request.payload.query else {
            throw AIShellError.requestError("Missing query for search")
        }

        guard enableRAG, let embeddingStore = embeddingStore else {
            throw AIShellError.requestError("RAG is not enabled")
        }

        let results = try await embeddingStore.search(
            query: query,
            limit: 5,
            minSimilarity: 0.6,
            workingDirectory: request.payload.workingDirectory
        )

        let formattedResults = results.map { result in
            let title = result.document.metadata.title ?? "Untitled"
            let similarity = String(format: "%.2f", result.similarity)
            return "[\(similarity)] \(title): \(String(result.document.content.prefix(100)))..."
        }

        return Response.success(
            requestId: request.id,
            commands: formattedResults,  // Reuse commands field
            processingTime: Date().timeIntervalSince(request.timestamp)
        )
    }
}

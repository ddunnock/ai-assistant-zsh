// Sources/AIShellDaemon/DaemonService.swift

import Foundation
import AIShellCore
import Logging

/// Main daemon service coordinator
actor DaemonService {
    private let configuration: Configuration
    private let logger = LoggerFactory.create(category: "daemon")

    private var socketServer: SocketServer?
    private var ollamaClient: OllamaClient?
    private var zaiClient: ZaiClient?

    // Phase 2 components
    private var memoryStore: MemoryStore?
    private var embeddingStore: EmbeddingStore?
    private var responseCache: ResponseCache?
    private var promptTemplates: PromptTemplates?

    private var isRunning = false

    // For graceful shutdown
    private var shutdownContinuation: CheckedContinuation<Void, Never>?
    private static var sharedInstance: DaemonService?

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    func start() async throws {
        guard !isRunning else {
            logger.warning("Daemon already running")
            return
        }

        logger.info("Starting AI Shell Daemon", metadata: [
            "socket": configuration.socketPath,
            "ollama": configuration.ollamaURL,
            "model": configuration.model,
            "memory": String(configuration.enableMemory),
            "rag": String(configuration.enableRAG),
            "cache": String(configuration.enableCache),
            "zai": String(configuration.enableZai)
        ])

        // Initialize Ollama client
        let ollama = OllamaClient(
            baseURL: configuration.ollamaURL,
            model: configuration.model
        )
        self.ollamaClient = ollama

        // Check Ollama health
        let isHealthy = await ollama.healthCheck()
        guard isHealthy else {
            throw AIShellError.ollamaError("Ollama is not responding. Is it running?")
        }

        logger.info("Ollama connection verified")

        // Initialize z.ai client if enabled
        var zai: ZaiClient?
        if configuration.enableZai {
            guard let apiKey = configuration.getZaiAPIKey() else {
                throw AIShellError.configurationError(
                    "Z.ai is enabled but no API key provided. Set zaiAPIKey in config or ZAI_API_KEY environment variable."
                )
            }

            zai = ZaiClient(
                baseURL: configuration.getZaiURL(),
                model: configuration.getZaiModel(),
                apiKey: apiKey
            )
            self.zaiClient = zai

            // Check z.ai health
            let isZaiHealthy = await zai!.healthCheck()
            guard isZaiHealthy else {
                throw AIShellError.zaiError("Z.ai API is not responding. Check your API key and network connection.")
            }

            logger.info("Z.ai connection verified", metadata: [
                "url": configuration.getZaiURL(),
                "model": configuration.getZaiModel()
            ])
        }

        // Initialize Phase 2 components
        try await initializePhase2Components(ollamaClient: ollama)

        // Create enhanced request handler with Phase 2 features
        let requestHandler = EnhancedRequestHandler(
            ollamaClient: ollama,
            zaiClient: zai,
            memoryStore: memoryStore,
            embeddingStore: embeddingStore,
            responseCache: responseCache,
            promptTemplates: promptTemplates ?? PromptTemplates(),
            enableMemory: configuration.enableMemory,
            enableRAG: configuration.enableRAG,
            enableCache: configuration.enableCache
        )

        // Start socket server
        let server = SocketServer(
            socketPath: configuration.socketPath,
            requestHandler: requestHandler
        )
        self.socketServer = server

        try await server.start()

        isRunning = true
        logger.info("Daemon started successfully")

        // Setup signal handlers
        await setupSignalHandlers()
    }

    private func initializePhase2Components(ollamaClient: OllamaClient) async throws {
        // Initialize Prompt Templates
        let promptsURL = configuration.storageURL(for: "prompts", defaultName: "prompts.json")
        let templates = PromptTemplates(storageURL: promptsURL)

        do {
            try await templates.load()
            logger.info("Loaded custom prompts")
        } catch {
            logger.info("Using default prompts")
        }

        self.promptTemplates = templates

        // Initialize Memory Store
        if configuration.enableMemory {
            let memoryURL = configuration.storageURL(for: "memory", defaultName: "memory.json")
            let memory = MemoryStore(storageURL: memoryURL)

            do {
                try await memory.load()
                logger.info("Loaded memory from disk")
            } catch {
                logger.warning("Failed to load memory store - starting fresh", metadata: [
                    "error": String(describing: error),
                    "path": memoryURL.path
                ])
            }

            self.memoryStore = memory
        }

        // Initialize RAG/Embedding Store
        if configuration.enableRAG {
            let ragURL = configuration.storageURL(for: "rag", defaultName: "embeddings.json")
            let embeddings = EmbeddingStore(storageURL: ragURL, ollamaClient: ollamaClient)

            do {
                try await embeddings.load()
                let stats = await embeddings.getStatistics()
                if let docCount = stats["total_documents"] as? Int {
                    logger.info("Loaded RAG store", metadata: ["documents": String(docCount)])
                }
            } catch {
                logger.warning("Failed to load RAG store - starting with empty store", metadata: [
                    "error": String(describing: error),
                    "path": ragURL.path
                ])
            }

            self.embeddingStore = embeddings
        }

        // Initialize Response Cache
        if configuration.enableCache {
            let cacheURL = configuration.storageURL(for: "cache", defaultName: "cache.json")
            let cache = ResponseCache(storageURL: cacheURL, enablePersistence: true, ollamaClient: ollamaClient)

            do {
                try await cache.load()
                let stats = await cache.getStatistics()
                logger.info("Loaded cache", metadata: ["entries": String(stats.totalEntries)])
            } catch {
                logger.warning("Failed to load cache - starting empty", metadata: [
                    "error": String(describing: error),
                    "path": cacheURL.path
                ])
            }

            self.responseCache = cache
        }
    }

    func stop() async {
        guard isRunning else { return }

        logger.info("Stopping daemon")

        // Save Phase 2 component state
        await savePhase2Components()

        if let server = socketServer {
            await server.stop()
        }

        // Remove PID file
        removePIDFile()

        isRunning = false
        logger.info("Daemon stopped")
    }

    private func savePhase2Components() async {
        // Save memory
        if let memory = memoryStore {
            do {
                try await memory.save()
                logger.info("Saved memory to disk")
            } catch {
                logger.error("Failed to save memory", error: error)
            }
        }

        // Save embeddings
        if let embeddings = embeddingStore {
            do {
                try await embeddings.save()
                logger.info("Saved RAG store to disk")
            } catch {
                logger.error("Failed to save RAG store", error: error)
            }
        }

        // Save cache
        if let cache = responseCache {
            do {
                try await cache.save()
                logger.info("Saved cache to disk")
            } catch {
                logger.error("Failed to save cache", error: error)
            }
        }

        // Save prompts
        if let prompts = promptTemplates {
            do {
                try await prompts.save()
                logger.info("Saved prompts to disk")
            } catch {
                logger.error("Failed to save prompts", error: error)
            }
        }
    }

    func run() async throws {
        // Store reference for signal handler
        DaemonService.sharedInstance = self

        try await start()

        // Keep running until interrupted
        logger.info("Daemon running. Press Ctrl+C to stop.")

        // Wait for shutdown signal
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await self.setShutdownContinuation(continuation)
            }
        }

        // Graceful shutdown
        await stop()

        logger.info("Shutdown complete")
    }

    private func setShutdownContinuation(_ continuation: CheckedContinuation<Void, Never>) {
        self.shutdownContinuation = continuation
        setupSignalHandlers()
    }

    private func setupSignalHandlers() {
        // Setup SIGINT handler (Ctrl+C)
        signal(SIGINT) { _ in
            print("\nReceived SIGINT, shutting down gracefully...")
            Task {
                await DaemonService.sharedInstance?.triggerShutdown()
            }
        }

        // Setup SIGTERM handler (kill command)
        signal(SIGTERM) { _ in
            print("\nReceived SIGTERM, shutting down gracefully...")
            Task {
                await DaemonService.sharedInstance?.triggerShutdown()
            }
        }
    }

    private func triggerShutdown() {
        guard let continuation = shutdownContinuation else { return }
        shutdownContinuation = nil
        continuation.resume()
    }

    /// Write PID file for process management
    func writePIDFile() throws {
        let pidDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ai-shell")
        let pidFile = pidDir.appendingPathComponent("daemon.pid")

        try FileManager.default.createDirectory(at: pidDir, withIntermediateDirectories: true)
        try String(ProcessInfo.processInfo.processIdentifier).write(to: pidFile, atomically: true, encoding: .utf8)
    }

    /// Remove PID file on shutdown
    private func removePIDFile() {
        let pidFile = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ai-shell/daemon.pid")
        try? FileManager.default.removeItem(at: pidFile)
    }
}

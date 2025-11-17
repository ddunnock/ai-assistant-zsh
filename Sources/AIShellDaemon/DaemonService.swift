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
    private var isRunning = false
    
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
            "model": configuration.model
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
        
        // Create request handler
        let requestHandler = RequestHandler(ollamaClient: ollama)
        
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
    
    func stop() async {
        guard isRunning else { return }
        
        logger.info("Stopping daemon")
        
        if let server = socketServer {
            await server.stop()
        }
        
        isRunning = false
        logger.info("Daemon stopped")
    }
    
    func run() async throws {
        try await start()
        
        // Keep running until interrupted
        logger.info("Daemon running. Press Ctrl+C to stop.")
        
        // Wait forever (until signal)
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            // Continuation will never resume, keeping the task alive until cancelled
        }
    }
    
    private func setupSignalHandlers() async {
        // Setup SIGINT and SIGTERM handlers
        signal(SIGINT) { _ in
            Task {
                await DaemonService.handleShutdown()
            }
        }
        
        signal(SIGTERM) { _ in
            Task {
                await DaemonService.handleShutdown()
            }
        }
    }
    
    private static func handleShutdown() async {
        print("\nReceived shutdown signal")
        // The actual service instance will be stopped by the main function
        exit(0)
    }
}
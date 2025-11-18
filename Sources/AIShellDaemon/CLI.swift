// Sources/AIShellDaemon/CLI.swift

import Foundation
import ArgumentParser
import AIShellCore

@main
public struct AIShellDaemonCLI: AsyncParsableCommand {
    public static let configuration = CommandConfiguration(
        commandName: "ai-shell-daemon",
        abstract: "AI-powered shell assistant daemon",
        version: "1.0.0"
    )

    @Option(name: .shortAndLong, help: "Path to configuration file")
    var config: String?

    @Option(name: .shortAndLong, help: "Socket path (overrides config)")
    var socket: String?

    @Flag(name: .shortAndLong, help: "Verbose logging")
    var verbose: Bool = false

    @Flag(name: .shortAndLong, help: "Quiet mode (suppress banner)")
    var quiet: Bool = false

    public init() {}

    public mutating func validate() throws {
        // Validation passed - no action needed in production
    }

    public func run() async throws {
        // Load configuration first
        var configuration: Configuration
        do {
            configuration = try Configuration.load(from: config)
            // Validate loaded configuration
            try configuration.validate()
        } catch {
            print("❌ Error loading configuration: \(error)")
            throw ExitCode.failure
        }

        // Override with command line options
        if let socket = socket {
            configuration = Configuration(
                socketPath: socket,
                ollamaURL: configuration.ollamaURL,
                model: configuration.model,
                logLevel: verbose ? "debug" : configuration.logLevel,
                enableMemory: configuration.enableMemory,
                enableRAG: configuration.enableRAG,
                enableCache: configuration.enableCache,
                enableStreaming: configuration.enableStreaming,
                memoryStoragePath: configuration.memoryStoragePath,
                ragStoragePath: configuration.ragStoragePath,
                cacheStoragePath: configuration.cacheStoragePath,
                promptsStoragePath: configuration.promptsStoragePath,
                maxMemoryAge: configuration.maxMemoryAge,
                maxCacheAge: configuration.maxCacheAge,
                ragMinSimilarity: configuration.ragMinSimilarity
            )
        } else if verbose {
            // Apply verbose flag even without socket override
            configuration = Configuration(
                socketPath: configuration.socketPath,
                ollamaURL: configuration.ollamaURL,
                model: configuration.model,
                logLevel: "debug",
                enableMemory: configuration.enableMemory,
                enableRAG: configuration.enableRAG,
                enableCache: configuration.enableCache,
                enableStreaming: configuration.enableStreaming,
                memoryStoragePath: configuration.memoryStoragePath,
                ragStoragePath: configuration.ragStoragePath,
                cacheStoragePath: configuration.cacheStoragePath,
                promptsStoragePath: configuration.promptsStoragePath,
                maxMemoryAge: configuration.maxMemoryAge,
                maxCacheAge: configuration.maxCacheAge,
                ragMinSimilarity: configuration.ragMinSimilarity
            )
        }

        // Validate final configuration after overrides
        do {
            try configuration.validate()
        } catch {
            print("❌ Configuration validation failed: \(error)")
            throw ExitCode.failure
        }

        // Configure global logger with the finalized log level
        LoggerFactory.configure(logLevel: configuration.logLevel)

        // Create logger for CLI
        let logger = LoggerFactory.create(category: "cli")

        logger.debug("Configuration loaded", metadata: [
            "socketPath": configuration.socketPath,
            "ollamaURL": configuration.ollamaURL,
            "model": configuration.model,
            "logLevel": configuration.logLevel
        ])

        // Show startup banner unless quiet mode
        if !quiet {
            print("🚀 AI Shell Assistant Daemon")
            print("Version: \(Self.configuration.version)")
            print()
        }

        // Create and run daemon
        logger.debug("Creating DaemonService")
        let daemon = DaemonService(configuration: configuration)

        do {
            logger.debug("Starting daemon service")
            try await daemon.run()
            logger.info("Daemon service completed normally")
        } catch {
            logger.error("Daemon service failed", error: error)
            print("❌ Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

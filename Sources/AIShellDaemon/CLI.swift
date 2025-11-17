// Sources/AIShellDaemon/CLI.swift

import Foundation
import ArgumentParser
import AIShellCore

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

    public init() {}

    public mutating func validate() throws {
        print("DEBUG: validate() called")
        print("DEBUG: config = \(String(describing: config))")
        print("DEBUG: socket = \(String(describing: socket))")
        print("DEBUG: verbose = \(verbose)")
    }

    public func run() async throws {
        print("DEBUG: run() called!")
        print("DEBUG: Thread: \(Thread.current)")
        print("🚀 AI Shell Assistant Daemon")
        print("Version: \(Self.configuration.version)")
        print()

        print("DEBUG: About to load configuration from: \(String(describing: config))")
        // Load configuration
        var configuration: Configuration
        do {
            configuration = try Configuration.load(from: config)
            print("DEBUG: Configuration loaded successfully")
        } catch {
            print("DEBUG: Configuration loading failed: \(error)")
            throw error
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
        }

        // Create and run daemon
        print("DEBUG: Creating DaemonService")
        let daemon = DaemonService(configuration: configuration)
        print("DEBUG: DaemonService created, about to call daemon.run()")

        do {
            print("DEBUG: Calling daemon.run()")
            try await daemon.run()
            print("DEBUG: daemon.run() completed")
        } catch {
            print("DEBUG: daemon.run() threw error: \(error)")
            print("❌ Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

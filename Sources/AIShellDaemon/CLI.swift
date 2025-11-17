// Sources/AIShellDaemon/CLI.swift

import Foundation
import ArgumentParser
import AIShellCore

struct AIShellDaemonCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
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
    
    func run() async throws {
        print("🚀 AI Shell Assistant Daemon")
        print("Version: \(Self.configuration.version)")
        print()
        
        // Load configuration
        var configuration = try Configuration.load(from: config)
        
        // Override with command line options
        if let socket = socket {
            configuration = Configuration(
                socketPath: socket,
                ollamaURL: configuration.ollamaURL,
                model: configuration.model,
                logLevel: verbose ? "debug" : configuration.logLevel
            )
        }
        
        // Create and run daemon
        let daemon = DaemonService(configuration: configuration)
        
        do {
            try await daemon.run()
        } catch {
            print("❌ Error: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}


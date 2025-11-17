// Sources/AIShellDaemon/Configuration.swift

import Foundation

/// Daemon configuration
struct Configuration: Codable {
    let socketPath: String
    let ollamaURL: String
    let model: String
    let logLevel: String
    
    static let `default` = Configuration(
        socketPath: "/tmp/ai-shell.sock",
        ollamaURL: "http://localhost:11434",
        model: "llama3.1:8b",
        logLevel: "info"
    )
    
    static func load(from path: String?) throws -> Configuration {
        guard let path = path else {
            return .default
        }
        
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(Configuration.self, from: data)
    }
}
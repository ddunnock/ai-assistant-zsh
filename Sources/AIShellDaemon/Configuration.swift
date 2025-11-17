// Sources/AIShellDaemon/Configuration.swift

import Foundation

/// Daemon configuration
struct Configuration: Codable {
    let socketPath: String
    let ollamaURL: String
    let model: String
    let logLevel: String

    // Phase 2 features
    let enableMemory: Bool
    let enableRAG: Bool
    let enableCache: Bool
    let enableStreaming: Bool

    let memoryStoragePath: String?
    let ragStoragePath: String?
    let cacheStoragePath: String?
    let promptsStoragePath: String?

    let maxMemoryAge: Int?  // hours
    let maxCacheAge: Int?   // days
    let ragMinSimilarity: Double?

    static let `default` = Configuration(
        socketPath: "/tmp/ai-shell.sock",
        ollamaURL: "http://localhost:11434",
        model: "llama3.1:8b",
        logLevel: "info",
        enableMemory: true,
        enableRAG: true,
        enableCache: true,
        enableStreaming: false,
        memoryStoragePath: nil,
        ragStoragePath: nil,
        cacheStoragePath: nil,
        promptsStoragePath: nil,
        maxMemoryAge: nil,
        maxCacheAge: nil,
        ragMinSimilarity: nil
    )

    static func load(from path: String?) throws -> Configuration {
        guard let path = path else {
            return .default
        }

        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()

        // Try to decode, but fall back to defaults for missing keys
        do {
            return try decoder.decode(Configuration.self, from: data)
        } catch {
            // If decode fails, try loading as partial config and merge with defaults
            let partial = try? JSONSerialization.jsonObject(with: data) as? [String: Any]

            if let partial = partial {
                return Configuration(
                    socketPath: partial["socketPath"] as? String ?? Configuration.default.socketPath,
                    ollamaURL: partial["ollamaURL"] as? String ?? Configuration.default.ollamaURL,
                    model: partial["model"] as? String ?? Configuration.default.model,
                    logLevel: partial["logLevel"] as? String ?? Configuration.default.logLevel,
                    enableMemory: partial["enableMemory"] as? Bool ?? Configuration.default.enableMemory,
                    enableRAG: partial["enableRAG"] as? Bool ?? Configuration.default.enableRAG,
                    enableCache: partial["enableCache"] as? Bool ?? Configuration.default.enableCache,
                    enableStreaming: partial["enableStreaming"] as? Bool ?? Configuration.default.enableStreaming,
                    memoryStoragePath: partial["memoryStoragePath"] as? String,
                    ragStoragePath: partial["ragStoragePath"] as? String,
                    cacheStoragePath: partial["cacheStoragePath"] as? String,
                    promptsStoragePath: partial["promptsStoragePath"] as? String,
                    maxMemoryAge: partial["maxMemoryAge"] as? Int,
                    maxCacheAge: partial["maxCacheAge"] as? Int,
                    ragMinSimilarity: partial["ragMinSimilarity"] as? Double
                )
            }

            throw error
        }
    }

    /// Get storage URL for component
    func storageURL(for component: String, defaultName: String) -> URL {
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let configDir = homeDir.appendingPathComponent(".config/ai-shell")

        switch component {
        case "memory":
            if let path = memoryStoragePath {
                return URL(fileURLWithPath: path)
            }
            return configDir.appendingPathComponent(defaultName)

        case "rag":
            if let path = ragStoragePath {
                return URL(fileURLWithPath: path)
            }
            return configDir.appendingPathComponent(defaultName)

        case "cache":
            if let path = cacheStoragePath {
                return URL(fileURLWithPath: path)
            }
            return configDir.appendingPathComponent(defaultName)

        case "prompts":
            if let path = promptsStoragePath {
                return URL(fileURLWithPath: path)
            }
            return configDir.appendingPathComponent(defaultName)

        default:
            return configDir.appendingPathComponent(defaultName)
        }
    }
}
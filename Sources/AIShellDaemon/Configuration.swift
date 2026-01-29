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

    // Z.ai configuration
    let enableZai: Bool
    let zaiAPIKey: String?
    let zaiURL: String?
    let zaiModel: String?

    /// Valid log level values
    private static let validLogLevels = Set(["debug", "info", "warning", "error"])

    /// Validate configuration values
    func validate() throws {
        // Validate log level
        guard Self.validLogLevels.contains(logLevel.lowercased()) else {
            throw ConfigurationError.invalidLogLevel(
                logLevel,
                valid: Array(Self.validLogLevels).sorted()
            )
        }

        // Validate Ollama URL format
        guard let url = URL(string: ollamaURL), url.scheme == "http" || url.scheme == "https" else {
            throw ConfigurationError.invalidURL("ollamaURL", ollamaURL)
        }

        // Validate model is not empty
        guard !model.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConfigurationError.emptyValue("model")
        }

        // Validate socket path is not empty
        guard !socketPath.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ConfigurationError.emptyValue("socketPath")
        }

        // Validate numeric ranges if provided
        if let maxMemoryAge = maxMemoryAge, maxMemoryAge < 1 {
            throw ConfigurationError.invalidRange("maxMemoryAge", min: 1, max: nil)
        }

        if let maxCacheAge = maxCacheAge, maxCacheAge < 1 {
            throw ConfigurationError.invalidRange("maxCacheAge", min: 1, max: nil)
        }

        if let ragMinSimilarity = ragMinSimilarity {
            guard ragMinSimilarity >= 0.0 && ragMinSimilarity <= 1.0 else {
                throw ConfigurationError.invalidRange("ragMinSimilarity", min: 0.0, max: 1.0)
            }
        }
    }

    /// Configuration-specific errors
    enum ConfigurationError: Error, CustomStringConvertible {
        case invalidLogLevel(String, valid: [String])
        case invalidURL(String, String)
        case emptyValue(String)
        case invalidRange(String, min: Any, max: Any?)

        var description: String {
            switch self {
            case .invalidLogLevel(let level, let valid):
                return "Invalid log level '\(level)'. Valid values: \(valid.joined(separator: ", "))"
            case .invalidURL(let field, let value):
                return "Invalid URL for '\(field)': \(value). Must start with http:// or https://"
            case .emptyValue(let field):
                return "Configuration field '\(field)' cannot be empty"
            case .invalidRange(let field, let min, let max):
                if let max = max {
                    return "Value for '\(field)' must be between \(min) and \(max)"
                } else {
                    return "Value for '\(field)' must be at least \(min)"
                }
            }
        }
    }

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
        ragMinSimilarity: nil,
        enableZai: false,
        zaiAPIKey: nil,
        zaiURL: nil,
        zaiModel: nil
    )

    /// Get z.ai API key from config or environment variable
    func getZaiAPIKey() -> String? {
        zaiAPIKey ?? ProcessInfo.processInfo.environment["ZAI_API_KEY"]
    }

    /// Get z.ai URL with default fallback
    func getZaiURL() -> String {
        zaiURL ?? "https://api.z.ai/api/paas/v4"
    }

    /// Get z.ai model with default fallback
    func getZaiModel() -> String {
        zaiModel ?? "glm-4.7"
    }

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
                    ragMinSimilarity: partial["ragMinSimilarity"] as? Double,
                    enableZai: partial["enableZai"] as? Bool ?? Configuration.default.enableZai,
                    zaiAPIKey: partial["zaiAPIKey"] as? String,
                    zaiURL: partial["zaiURL"] as? String,
                    zaiModel: partial["zaiModel"] as? String
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

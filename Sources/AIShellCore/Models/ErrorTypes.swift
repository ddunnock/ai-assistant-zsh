// Sources/AIShellCore/Models/ErrorTypes.swift

import Foundation

/// Custom errors for the AI Shell Assistant
public enum AIShellError: Error, CustomStringConvertible {
    case socketError(String)
    case ollamaError(String)
    case connectionError(String)
    case requestError(String)
    case timeoutError(String)
    case configurationError(String)
    case validationError(String)
    
    public var description: String {
        switch self {
        case .socketError(let msg):
            return "Socket error: \(msg)"
        case .ollamaError(let msg):
            return "Ollama error: \(msg)"
        case .connectionError(let msg):
            return "Connection error: \(msg)"
        case .requestError(let msg):
            return "Request error: \(msg)"
        case .timeoutError(let msg):
            return "Timeout error: \(msg)"
        case .configurationError(let msg):
            return "Configuration error: \(msg)"
        case .validationError(let msg):
            return "Validation error: \(msg)"
        }
    }
    
    public var errorCode: String {
        switch self {
        case .socketError: return "SOCKET_ERROR"
        case .ollamaError: return "OLLAMA_ERROR"
        case .connectionError: return "CONNECTION_ERROR"
        case .requestError: return "REQUEST_ERROR"
        case .timeoutError: return "TIMEOUT_ERROR"
        case .configurationError: return "CONFIG_ERROR"
        case .validationError: return "VALIDATION_ERROR"
        }
    }
}
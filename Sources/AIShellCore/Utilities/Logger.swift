// Sources/AIShellCore/Utilities/Logger.swift

import Foundation
import Logging
import os.log

/// Unified logging system
public struct AppLogger {
    private let logger: Logging.Logger
    private let osLog: OSLog

    public init(subsystem: String, category: String, logLevel: Logging.Logger.Level = .info) {
        var logger = Logging.Logger(label: "\(subsystem).\(category)")
        logger.logLevel = logLevel
        self.logger = logger
        self.osLog = OSLog(subsystem: subsystem, category: category)
    }
    
    public func debug(_ message: String, metadata: [String: String]? = nil) {
        if let metadata = metadata {
            logger.debug("\(message)", metadata: convertMetadata(metadata))
        } else {
            logger.debug("\(message)")
        }
        
        if #available(macOS 11.0, *) {
            os_log(.debug, log: osLog, "%{public}@", message)
        }
    }
    
    public func info(_ message: String, metadata: [String: String]? = nil) {
        if let metadata = metadata {
            logger.info("\(message)", metadata: convertMetadata(metadata))
        } else {
            logger.info("\(message)")
        }
        
        if #available(macOS 11.0, *) {
            os_log(.info, log: osLog, "%{public}@", message)
        }
    }
    
    public func warning(_ message: String, metadata: [String: String]? = nil) {
        if let metadata = metadata {
            logger.warning("\(message)", metadata: convertMetadata(metadata))
        } else {
            logger.warning("\(message)")
        }
        
        if #available(macOS 11.0, *) {
            os_log(.default, log: osLog, "%{public}@", message)
        }
    }
    
    public func error(_ message: String, error: Error? = nil, metadata: [String: String]? = nil) {
        var fullMetadata = metadata ?? [:]
        if let error = error {
            fullMetadata["error"] = String(describing: error)
        }
        
        logger.error("\(message)", metadata: convertMetadata(fullMetadata))
        
        if #available(macOS 11.0, *) {
            let errorMsg = error != nil ? "\(message): \(String(describing: error!))" : message
            os_log(.error, log: osLog, "%{public}@", errorMsg)
        }
    }
    
    private func convertMetadata(_ dict: [String: String]) -> Logging.Logger.Metadata {
        dict.mapValues { Logging.Logger.MetadataValue.string($0) }
    }
}

// MARK: - Global Logger Factory

public enum LoggerFactory {
    private static let subsystem = "com.aishell"
    private static var configuredLogLevel: Logging.Logger.Level = .info

    /// Configure the global log level for all loggers
    /// - Parameter logLevel: String value - "debug", "info", "warning", or "error"
    public static func configure(logLevel: String) {
        configuredLogLevel = mapLogLevel(logLevel)
    }

    public static func create(category: String) -> AppLogger {
        AppLogger(subsystem: subsystem, category: category, logLevel: configuredLogLevel)
    }

    /// Map string log level to Logger.Level enum
    private static func mapLogLevel(_ level: String) -> Logging.Logger.Level {
        switch level.lowercased() {
        case "debug":
            return .debug
        case "info":
            return .info
        case "warning":
            return .warning
        case "error":
            return .error
        default:
            // Default to info for invalid values
            return .info
        }
    }
}
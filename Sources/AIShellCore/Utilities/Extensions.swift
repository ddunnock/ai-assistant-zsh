// Sources/AIShellCore/Utilities/Extensions.swift

import Foundation
import NIOCore

// MARK: - Data Extensions

extension Data {
    /// Convert to pretty-printed JSON string
    var prettyJSON: String? {
        guard let object = try? JSONSerialization.jsonObject(with: self),
              let data = try? JSONSerialization.data(
                withJSONObject: object,
                options: [.prettyPrinted, .sortedKeys]
              ),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}

// MARK: - ByteBuffer Extensions

extension ByteBuffer {
    /// Create from Data
    init(data: Data) {
        var buffer = ByteBufferAllocator().buffer(capacity: data.count)
        buffer.writeBytes(data)
        self = buffer
    }
    
    /// Convert to Data
    func toData() -> Data? {
        return self.getData(at: 0, length: self.readableBytes)
    }
}

// MARK: - String Extensions

extension String {
    /// Truncate string to specified length
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length - trailing.count)) + trailing
    }
    
    /// Remove ANSI color codes
    var withoutANSI: String {
        return self.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[a-zA-Z]",
            with: "",
            options: .regularExpression
        )
    }
}

// MARK: - TimeInterval Extensions

extension TimeInterval {
    /// Format as milliseconds
    var milliseconds: String {
        String(format: "%.2fms", self * 1000)
    }
    
    /// Format as seconds
    var seconds: String {
        String(format: "%.2fs", self)
    }
}

// MARK: - Result Extensions

extension Result {
    /// Get value or nil
    var value: Success? {
        switch self {
        case .success(let value):
            return value
        case .failure:
            return nil
        }
    }
    
    /// Get error or nil
    var error: Failure? {
        switch self {
        case .success:
            return nil
        case .failure(let error):
            return error
        }
    }
}
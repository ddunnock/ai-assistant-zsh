// Sources/AIShellCore/Server/Protocol.swift

import Foundation

/// Protocol version for compatibility checking
public enum ProtocolVersion {
    public static let current = "1.0.0"
}

/// Message framing for socket communication
public struct FramedMessage {
    public let length: UInt32
    public let data: Data
    
    public init(data: Data) {
        self.length = UInt32(data.count)
        self.data = data
    }
    
    /// Encode message with length prefix
    public func encoded() -> Data {
        var encoded = Data()
        
        // Write length as big-endian UInt32
        var length = self.length.bigEndian
        encoded.append(Data(bytes: &length, count: MemoryLayout<UInt32>.size))
        
        // Write data
        encoded.append(data)
        
        return encoded
    }
    
    /// Decode message from data
    public static func decode(from data: Data) throws -> FramedMessage {
        guard data.count >= MemoryLayout<UInt32>.size else {
            throw AIShellError.requestError("Insufficient data for length prefix")
        }
        
        // Read length
        let lengthData = data.prefix(MemoryLayout<UInt32>.size)
        let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
        
        // Read message data
        let messageStart = MemoryLayout<UInt32>.size
        let messageEnd = messageStart + Int(length)
        
        guard data.count >= messageEnd else {
            throw AIShellError.requestError("Incomplete message data")
        }
        
        let messageData = data.subdata(in: messageStart..<messageEnd)
        
        return FramedMessage(data: messageData)
    }
}
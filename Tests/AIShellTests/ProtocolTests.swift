// Tests/AIShellTests/ProtocolTests.swift

import XCTest
@testable import AIShellCore

class ProtocolTests: XCTestCase {
    func testFramedMessageEncoding() throws {
        let originalData = "Hello, World!".data(using: .utf8)!
        let message = FramedMessage(data: originalData)
        
        let encoded = message.encoded()
        
        // Should have 4 bytes for length + data
        XCTAssertEqual(encoded.count, 4 + originalData.count)
        
        // Decode
        let decoded = try FramedMessage.decode(from: encoded)
        
        XCTAssertEqual(decoded.data, originalData)
        XCTAssertEqual(decoded.length, UInt32(originalData.count))
    }
    
    func testRequestSerialization() throws {
        let request = Request.explain(command: "ls -la")
        
        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(Request.self, from: data)
        
        XCTAssertEqual(decoded.id, request.id)
        XCTAssertEqual(decoded.type, request.type)
        XCTAssertEqual(decoded.payload.command, request.payload.command)
    }
    
    func testResponseSerialization() throws {
        let response = Response.success(
            requestId: "test-123",
            explanation: "This is a test"
        )
        
        let data = try JSONEncoder().encode(response)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        
        XCTAssertEqual(decoded.requestId, response.requestId)
        XCTAssertEqual(decoded.status, response.status)
        XCTAssertEqual(decoded.payload.explanation, response.payload.explanation)
    }
}
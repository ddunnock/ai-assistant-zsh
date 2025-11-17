// Tests/AIShellTests/RequestHandlerTests.swift

import XCTest
@testable import AIShellCore

final class RequestHandlerTests: XCTestCase {
    var handler: RequestHandler!
    var ollamaClient: OllamaClient!
    
    override func setUp() async throws {
        ollamaClient = OllamaClient()
        
        let isHealthy = await ollamaClient.healthCheck()
        guard isHealthy else {
            throw XCTSkip("Ollama is not running")
        }
        
        handler = RequestHandler(ollamaClient: ollamaClient)
    }
    
    func testHealthRequest() async {
        let request = Request.health()
        let response = await handler.handle(request)
        
        XCTAssertEqual(response.status, .success)
        XCTAssertEqual(response.requestId, request.id)
    }
    
    func testExplainRequest() async {
        let request = Request.explain(command: "ls -la")
        let response = await handler.handle(request)
        
        XCTAssertEqual(response.status, .success)
        XCTAssertNotNil(response.payload.explanation)
        XCTAssertFalse(response.payload.explanation!.isEmpty)
    }
    
    func testSuggestRequest() async {
        let request = Request.suggest(
            command: "git co",
            workingDirectory: "/tmp"
        )
        let response = await handler.handle(request)
        
        XCTAssertEqual(response.status, .success)
        XCTAssertNotNil(response.payload.suggestion)
    }
    
    func testInvalidRequest() async {
        let request = Request(
            type: .explain,
            payload: Request.Payload() // Missing command
        )
        let response = await handler.handle(request)
        
        XCTAssertEqual(response.status, .error)
        XCTAssertNotNil(response.payload.error)
    }
}
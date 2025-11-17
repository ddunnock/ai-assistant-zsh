// Tests/AIShellTests/OllamaClientTests.swift

import XCTest
@testable import AIShellCore

final class OllamaClientTests: XCTestCase {
    var client: OllamaClient!
    
    override func setUp() async throws {
        client = OllamaClient()
        
        // Skip if Ollama is not running
        let isHealthy = await client.healthCheck()
        guard isHealthy else {
            throw XCTSkip("Ollama is not running")
        }
    }
    
    func testGenerate() async throws {
        let response = try await client.generate(
            prompt: "Say 'Hello World' and nothing else.",
            system: "You are a test assistant. Follow instructions exactly."
        )
        
        XCTAssertFalse(response.isEmpty)
        XCTAssertTrue(response.lowercased().contains("hello"))
    }
    
    func testChat() async throws {
        let messages = [
            OllamaChatMessage.system("You are a helpful assistant."),
            OllamaChatMessage.user("What is 2+2? Reply with only the number.")
        ]
        
        let response = try await client.chat(messages: messages)
        
        XCTAssertFalse(response.isEmpty)
        XCTAssertTrue(response.contains("4"))
    }
    
    func testListModels() async throws {
        let models = try await client.listModels()
        
        XCTAssertFalse(models.isEmpty)
        XCTAssertTrue(models.contains { $0.name.contains("llama") })
    }
    
    func testHealthCheck() async {
        let isHealthy = await client.healthCheck()
        XCTAssertTrue(isHealthy)
    }
}
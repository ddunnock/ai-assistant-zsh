# Coding Conventions

**Analysis Date:** 2026-01-23

## Naming Patterns

**Files:**
- PascalCase for class/struct/enum names: `CommandSafetyChecker.swift`, `OllamaClient.swift`, `RequestHandler.swift`
- Descriptive names reflecting content: `ErrorTypes.swift`, `PromptTemplates.swift`, `InputValidator.swift`
- Test files follow pattern: `[UnitName]Tests.swift` e.g., `CommandSafetyCheckerTests.swift`

**Functions:**
- camelCase for all functions and methods
- Public API methods use descriptive verbs: `generate()`, `listModels()`, `healthCheck()`, `validateCommand()`
- Private helper methods use lowercase with clear purpose: `post()`, `get()`, `postStream()`, `buildSuggestPrompt()`
- Test functions use pattern `test[Feature][Scenario]()`: `testSafeCommand_NoWarnings()`, `testDestructiveDelete_RmRf()`

**Variables:**
- camelCase for all variables and properties
- Boolean variables often start with `is` or `has`: `isHealthy`, `hasHighSeverityWarnings`
- Private properties prefixed with underscore not used; rely on `private` keyword
- Constants use camelCase: `maxCommandLength`, `maxTaskLength`

**Types:**
- PascalCase for all types: `Request`, `Response`, `AIShellError`, `RequestType`
- Nested types declared within their parent type (nested enums, structs)
- Enum cases use camelCase: `.destructiveDelete`, `.systemModification`, `.suggest`, `.explain`

## Code Style

**Formatting:**
- Swift 5.9 as minimum version (see `Package.swift`)
- 4-space indentation (Swift standard)
- Line length appears to be around 100-120 characters based on code samples
- No explicit formatter configured; follows Swift conventions

**Linting:**
- No `.swiftlint.yml` or linter configuration detected
- Code follows Swift style guide conventions implicitly

## Import Organization

**Order:**
1. Foundation (system framework)
2. Other system frameworks (NIOCore, NIOHTTP1, Logging, etc.)
3. Internal modules (AIShellCore)

**Example from `OllamaClient.swift`:**
```swift
import Foundation
import AsyncHTTPClient
import NIOCore
import NIOHTTP1
```

**Path Aliases:**
- Not used; full module paths used (no `typealias` or shorthand imports detected)

## Error Handling

**Patterns:**
- Custom error enum `AIShellError` with associated values: `case socketError(String)`, `case ollamaError(String)`
- Custom error enum `ValidationError` with tagged cases: `case inputTooLong(field: String, maxLength: Int, actualLength: Int)`
- All errors conform to `Error` protocol
- `CustomStringConvertible` implemented on error types with descriptive `description` computed property
- Errors include `errorCode` property for programmatic handling (e.g., "SOCKET_ERROR", "VALIDATION_ERROR")
- Validation errors implement `LocalizedError` with `errorDescription` property
- Errors thrown with associated context for debugging: `throw ValidationError.emptyInput(field: "command")`
- Error responses in handlers wrap errors in structured format with code, message, and optional details

**Error Handling Approach:**
```swift
do {
    let response = try await processRequest(request)
    // Handle success
} catch {
    logger.error("Request failed", error: error, metadata: [...])
    return errorResponse(for: request, error: error)
}
```

## Logging

**Framework:** Apple Logging package (`swift-log`) combined with `os.log` for system logging

**Implementation:**
- Centralized logger factory: `LoggerFactory.create(category: String)` in `Logger.swift`
- Unified `AppLogger` struct wraps both `Logging.Logger` and `OSLog`
- Logger initialization: `let logger = LoggerFactory.create(category: "ollama")`

**Patterns:**
- Debug level for detailed operational info: `logger.debug("Generating completion", metadata: [...])`
- Info level for successful operations: `logger.info("Generation complete", metadata: [...])`
- Warning level for notable conditions: `logger.warning(...)`
- Error level includes optional error parameter: `logger.error("Health check failed", error: error)`
- Metadata passed as optional `[String: String]` dictionary for structured logging
- Duration/timing logged as milliseconds: `"duration": duration.milliseconds`
- Response metrics included in metadata: `"response_length": String(response.count)`

**Examples:**
```swift
logger.debug("Generating completion", metadata: [
    "model": model,
    "prompt_length": String(prompt.count)
])

logger.error("Request failed", error: error, metadata: [
    "id": request.id
])
```

## Comments

**When to Comment:**
- File-level comments with `// [Path/To/File]` at the very top
- Triple-slash documentation comments for public types and methods
- MARK comments used to organize code sections: `// MARK: - Section Name`
- Inline comments used sparingly, only for non-obvious logic
- Comments above complex regex patterns explain their purpose

**JSDoc/TSDoc:**
- Not applicable (Swift codebase, not JavaScript/TypeScript)
- Triple-slash documentation (`///`) used for public API documentation:
```swift
/// Check a command for safety warnings
/// - Parameter command: The command to check
/// - Returns: Array of safety warnings found
public static func check(_ command: String) -> [SafetyWarning]
```

## Function Design

**Size:**
- Small, focused functions preferred
- Handler methods average 10-30 lines
- Complex logic split into private helper methods
- Example: `generate()` calls private `post()` helper

**Parameters:**
- Explicit parameter names required (Swift enforces this)
- Parameters use descriptive names: `prompt`, `system`, `endpoint`, `body`
- Optional parameters have default values: `system: String? = nil`, `metadata: [String: String]? = nil`
- Generic type parameters named clearly: `<T: Encodable, R: Decodable>`

**Return Values:**
- Explicit return types always specified: `async throws -> String`
- Empty initializers use initializer pattern rather than factory methods
- Convenience initializers provided as static methods on extensions:
```swift
extension Request {
    public static func suggest(command: String, workingDirectory: String) -> Request
}
```

## Module Design

**Exports:**
- All public types marked with `public` keyword
- Structs and classes made `public` to enable cross-module access
- Only necessary types exported; internal helpers remain `private` or `internal`
- Actors marked `public` to allow actor isolation across modules: `public actor OllamaClient`

**Barrel Files:**
- No barrel/index files detected
- Direct imports from specific modules used: `@testable import AIShellCore`

## Struct and Actor Usage

**Structs:**
- Used for value types: `Request`, `Response`, `AppLogger`, `CommandSafetyChecker`
- Conformance to protocols: `Codable`, `Sendable`, `Equatable`
- Nested types used: `Request.RequestType`, `Request.Payload`, `Response.Status`

**Actors:**
- Used for reference types with actor isolation: `OllamaClient`, `RequestHandler`
- Provides thread-safe access to shared resources (HTTP client, logger)
- Methods marked with `async` for concurrent access

## Protocol Conformance

**Common Conformances:**
- `Codable` for JSON serialization: `Request`, `Response`, `OllamaModels`
- `Sendable` for thread-safe sharing: All model types conform
- `CustomStringConvertible` for error types with custom description
- `Equatable` for comparing enum cases: `SafetyWarning`, `Severity`
- `Comparable` for ordering: `Severity` enum implements `<` operator
- `LocalizedError` for user-facing error messages

## Initialization Patterns

**Memberwise Initializers:**
- Implicit memberwise initializers used on public structs
- Custom initializers provided with default values:
```swift
public init(
    id: String = UUID().uuidString,
    type: RequestType,
    payload: Payload,
    timestamp: Date = Date()
)
```

**Factory Methods:**
- Static factory methods for convenience: `Request.suggest()`, `Request.explain()`, `Response.success()`
- Factory pattern used in `LoggerFactory.create(category:)`

---

*Convention analysis: 2026-01-23*

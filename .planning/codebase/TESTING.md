# Testing Patterns

**Analysis Date:** 2026-01-23

## Test Framework

**Runner:**
- XCTest (Apple's native testing framework)
- Config: `Package.swift` defines test target as `.testTarget(name: "AIShellTests", dependencies: ["AIShellCore"])`

**Assertion Library:**
- XCTest assertions: `XCTAssertTrue()`, `XCTAssertEqual()`, `XCTAssertFalse()`, `XCTAssertNotNil()`, `XCTAssertThrowsError()`

**Run Commands:**
```bash
swift test                    # Run all tests
swift test --enable-testing   # Build and run with testing enabled
swift build -c debug          # Build for testing
```

## Test File Organization

**Location:**
- Co-located in `Tests/AIShellTests/` directory separate from source
- Pattern: One test file per module/component being tested
- Test files mirror source structure conceptually

**Naming:**
- Convention: `[TargetName]Tests.swift`
- Examples: `CommandSafetyCheckerTests.swift`, `InputValidatorTests.swift`, `OllamaClientTests.swift`, `RequestHandlerTests.swift`

**Structure:**
```
Tests/
└── AIShellTests/
    ├── CommandSafetyCheckerTests.swift
    ├── InputValidatorTests.swift
    ├── MockOllamaClient.swift
    ├── OllamaClientTests.swift
    ├── ProtocolTests.swift
    └── RequestHandlerTests.swift
```

## Test Structure

**Suite Organization:**
```swift
import XCTest
@testable import AIShellCore

final class CommandSafetyCheckerTests: XCTestCase {

    // MARK: - Safe Command Tests

    func testSafeCommand_NoWarnings() {
        let warnings = CommandSafetyChecker.check("ls -la")
        XCTAssertTrue(warnings.isEmpty)
    }

    // MARK: - Destructive Delete Tests

    func testDestructiveDelete_RmRf() {
        let warnings = CommandSafetyChecker.check("rm -rf /tmp/test")
        XCTAssertTrue(warnings.contains(.destructiveDelete))
    }
}
```

**Patterns:**
- Test class inherits from `XCTestCase`
- Methods prefixed with `test` (required by XCTest)
- MARK sections organize related tests by category
- Each test is independent and focused on single behavior
- Setup performed in `setUp()` method (async-compatible)
- Teardown in `tearDown()` method if needed

## Mocking

**Framework:** No external mocking library detected; uses native Swift approach

**Patterns:**
```swift
// MockOllamaClient.swift example:
class MockOllamaClient {
    // Custom mock implementation
}
```

**What to Mock:**
- External API clients (Ollama) for unit tests
- Replace real HTTP calls with test doubles
- Verify interactions without dependencies

**What NOT to Mock:**
- Value types (Request, Response, domain models)
- Pure business logic (CommandSafetyChecker, InputValidator)
- Static validation methods

## Fixtures and Factories

**Test Data:**
- Request factory methods used in tests: `Request.suggest()`, `Request.explain()`, `Request.health()`
- Inline data creation for simple values

**Location:**
- Test utilities and helpers in `Tests/AIShellTests/`
- `MockOllamaClient.swift` provides test doubles for external dependencies

**Example from test:**
```swift
override func setUp() async throws {
    ollamaClient = OllamaClient()

    let isHealthy = await ollamaClient.healthCheck()
    guard isHealthy else {
        throw XCTSkip("Ollama is not running")
    }

    handler = RequestHandler(ollamaClient: ollamaClient)
}
```

## Coverage

**Requirements:** No coverage requirements enforced

**View Coverage:**
- Run with coverage: `swift test --enable-code-coverage`
- Coverage data generated in `.build/debug/codecov/`

## Test Types

**Unit Tests:**
- Scope: Individual components in isolation
- Approach: Test pure functions and value types
- Examples: `CommandSafetyCheckerTests`, `InputValidatorTests` test validation logic without external dependencies
- Pattern: Call function with input, assert expected output
```swift
func testDestructiveDelete_RmRf() {
    let warnings = CommandSafetyChecker.check("rm -rf /tmp/test")
    XCTAssertTrue(warnings.contains(.destructiveDelete))
}
```

**Integration Tests:**
- Scope: Multiple components working together
- Approach: Test with real Ollama client, request handler processes full requests
- Examples: `OllamaClientTests`, `RequestHandlerTests`
- Pattern: Skip tests if external dependencies unavailable
```swift
override func setUp() async throws {
    client = OllamaClient()

    let isHealthy = await client.healthCheck()
    guard isHealthy else {
        throw XCTSkip("Ollama is not running")
    }
}
```

**E2E Tests:**
- Framework: Not used
- Integration tests serve as closest functional tests

## Common Patterns

**Async Testing:**
- Test methods declared `func testName() async throws`
- Setup methods: `override func setUp() async throws`
- Await async calls: `let isHealthy = await client.healthCheck()`
- Skip unavailable tests: `throw XCTSkip("Ollama is not running")`

```swift
func testGenerate() async throws {
    let response = try await client.generate(
        prompt: "Say 'Hello World' and nothing else.",
        system: "You are a test assistant."
    )

    XCTAssertFalse(response.isEmpty)
    XCTAssertTrue(response.lowercased().contains("hello"))
}
```

**Error Testing:**
- Pattern: `XCTAssertThrowsError` with error case matching
- Check error type and associated values

```swift
func testValidateCommand_EmptyCommand() {
    XCTAssertThrowsError(try InputValidator.validateCommand("")) { error in
        guard case InputValidator.ValidationError.emptyInput(let field) = error else {
            XCTFail("Expected emptyInput error")
            return
        }
        XCTAssertEqual(field, "command")
    }
}
```

**Grouped Test Cases:**
- Tests grouped by category using MARK sections
- Each category tests related scenarios:
  - `MARK: - Safe Command Tests`
  - `MARK: - Destructive Delete Tests`
  - `MARK: - System Modification Tests`
  - etc.

**Collection Assertions:**
```swift
func testCheckAll_MixedCommands() {
    let commands = [
        "ls -la",
        "rm -rf /tmp/test",
        "echo hello",
        "sudo systemctl restart nginx"
    ]

    let results = CommandSafetyChecker.checkAll(commands)

    XCTAssertEqual(results.count, 2)
    XCTAssertEqual(results[0].command, "rm -rf /tmp/test")
    XCTAssertTrue(results[0].warnings.contains(.destructiveDelete))
}
```

## Test Characteristics

**Independence:**
- Each test runs independently
- No test depends on another's results
- Setup/teardown ensures clean state

**Clarity:**
- Descriptive test names explain what is being tested
- Pattern: `test[Feature]_[Scenario]`
- Clear assertion messages

**Speed:**
- Unit tests run immediately (validation logic)
- Integration tests skip gracefully if Ollama unavailable
- No artificial delays or slow operations

**Maintainability:**
- MARK sections keep related tests organized
- Consistent patterns across test files
- Clear error messages aid debugging

## Test Statistics

**Current Test Count:**
- 6 test files in `Tests/AIShellTests/`
- 197 test cases in `CommandSafetyCheckerTests.swift` alone (comprehensive safety checks)
- 23 test cases in `InputValidatorTests.swift` (validation scenarios)
- 6 test cases in `OllamaClientTests.swift` (integration)
- 4 test cases in `RequestHandlerTests.swift` (integration)

**Coverage Areas:**
- Safety validation: Comprehensive (8 categories of dangerous patterns)
- Input validation: Comprehensive (all validators tested)
- Integration: Partial (depends on Ollama availability)
- Error handling: Tested via `XCTAssertThrowsError` pattern

---

*Testing analysis: 2026-01-23*

# Contributing to AI Shell Assistant

Thank you for your interest in contributing to AI Shell Assistant! This document provides guidelines and instructions for contributing.

## Code of Conduct

Be respectful, inclusive, and constructive. We're all here to build something useful together.

## How to Contribute

### Reporting Bugs

1. **Check existing issues** to avoid duplicates
2. **Create a new issue** with:
   - Clear title describing the problem
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (OS, Swift version, Ollama version)
   - Relevant logs or screenshots

**Template:**
```markdown
**Environment:**
- OS: macOS 14.0 / Ubuntu 22.04
- Swift: 5.9.2
- Ollama: 0.1.17
- Model: llama3.1:8b

**Steps to Reproduce:**
1. Run command X
2. Press Ctrl+Space
3. Observe error Y

**Expected:** Should suggest Z
**Actual:** Error message shown

**Logs:**
```
[paste relevant logs]
```
```

### Suggesting Features

1. **Check roadmap** in README.md
2. **Create an issue** with tag `enhancement`
3. **Describe the use case** and benefits
4. **Propose implementation** if you have ideas

### Submitting Code

#### Setup Development Environment

```bash
# Fork and clone
git clone https://github.com/yourusername/ai-assistant-zsh.git
cd ai-assistant-zsh

# Build
./build.sh --debug

# Run tests
swift test

# Install for testing
./install.sh --debug
```

#### Development Workflow

1. **Create a branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

2. **Make changes**
   - Write clean, documented code
   - Follow existing code style
   - Add tests for new functionality

3. **Test thoroughly**
   ```bash
   ./build.sh --clean --test
   ```

4. **Commit with clear messages**
   ```bash
   git commit -m "Add feature: brief description"
   ```

5. **Push and create PR**
   ```bash
   git push origin feature/your-feature-name
   ```
   Then create a Pull Request on GitHub

#### Pull Request Guidelines

- **Title:** Clear, concise description of changes
- **Description:** Explain what and why (not just how)
- **Link issues:** Reference related issues with `Fixes #123`
- **Tests:** Include tests for new features
- **Documentation:** Update README/docs if needed
- **Small PRs:** Keep changes focused and reviewable

**PR Template:**
```markdown
## Summary
Brief description of changes

## Motivation
Why are these changes needed?

## Changes
- Added X
- Modified Y
- Fixed Z

## Testing
- [ ] Unit tests pass
- [ ] Integration tests pass
- [ ] Manually tested on macOS/Linux

## Related Issues
Fixes #123
```

## Code Style

### Swift Code

Follow [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/)

**Key points:**
- Use descriptive names: `generateCompletion()` not `gen()`
- Prefer actors for mutable state
- Use `async`/`await` for asynchronous code
- Document public APIs with doc comments

**Example:**
```swift
/// Generates an AI completion for the given prompt
///
/// - Parameters:
///   - prompt: The user's input prompt
///   - system: Optional system message for context
/// - Returns: The generated completion text
/// - Throws: AIShellError if generation fails
public func generate(
    prompt: String,
    system: String? = nil
) async throws -> String {
    // Implementation
}
```

### Shell Script Code

**Key points:**
- Use `set -euo pipefail` for safety
- Quote variables: `"$variable"` not `$variable`
- Use functions for reusability
- Add comments for complex logic

**Example:**
```bash
#!/usr/bin/env bash
set -euo pipefail

# Configuration
readonly INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# Install binary to specified directory
install_binary() {
    local binary_path="$1"
    local target_dir="$2"

    cp "$binary_path" "$target_dir"
    chmod +x "$target_dir/$(basename "$binary_path")"
}
```

### ZSH Code

**Key points:**
- Use local variables: `local var="value"`
- Check command availability: `command -v cmd >/dev/null`
- Handle errors gracefully
- Use descriptive function names with `_ai_shell_` prefix

**Example:**
```zsh
# Get AI suggestion for command
ai_shell_suggest() {
    local command="${1:-$BUFFER}"
    [[ -z "$command" ]] && return 1

    local request=$(_ai_shell_create_request "suggest" "$command")
    local response=$(_ai_shell_send_request "$request")

    # Parse and return suggestion
    echo "$response" | jq -r '.payload.suggestion // ""'
}
```

## Project Structure

```
ai-assistant-zsh/
├── Sources/
│   ├── AIShellDaemon/          # Daemon executable
│   │   ├── main.swift          # CLI entry point
│   │   ├── Configuration.swift # Config management
│   │   └── DaemonService.swift # Service coordination
│   └── AIShellCore/            # Core library
│       ├── Clients/            # External API clients
│       │   ├── OllamaClient.swift
│       │   └── OllamaModels.swift
│       ├── Models/             # Data models
│       │   ├── Request.swift
│       │   ├── Response.swift
│       │   └── ErrorTypes.swift
│       ├── Server/             # Socket server
│       │   ├── Protocol.swift
│       │   ├── SocketServer.swift
│       │   └── RequestHandler.swift
│       └── Utilities/          # Helpers
│           ├── Logger.swift
│           └── Extensions.swift
├── Tests/
│   └── AIShellTests/           # Tests
├── zsh/                        # ZSH integration
│   └── ai-assistant.zsh
├── docs/                       # Documentation
└── scripts/                    # Build/install scripts
```

## Adding Features

### Adding a New Request Type

1. **Update Models** (`Sources/AIShellCore/Models/Request.swift`)
   ```swift
   enum RequestType: String, Codable {
       case suggest
       case explain
       case task
       case health
       case myNewType  // Add new type
   }
   ```

2. **Update RequestHandler** (`Sources/AIShellCore/Server/RequestHandler.swift`)
   ```swift
   private func processRequest(_ request: Request) async throws -> Response {
       switch request.type {
       case .suggest: return try await handleSuggest(request)
       case .explain: return try await handleExplain(request)
       case .task: return try await handleTask(request)
       case .health: return await handleHealth(request)
       case .myNewType: return try await handleMyNewType(request)  // Add handler
       }
   }

   private func handleMyNewType(_ request: Request) async throws -> Response {
       // Implementation
   }
   ```

3. **Update ZSH Plugin** (`zsh/ai-assistant.zsh`)
   ```zsh
   ai_shell_my_feature() {
       local input="$1"
       local request=$(_ai_shell_create_request "myNewType" "$input")
       local response=$(_ai_shell_send_request "$request")
       # Handle response
   }
   ```

4. **Add Tests**
   ```swift
   func testMyNewType() async throws {
       // Test implementation
   }
   ```

### Adding a New Ollama Endpoint

1. **Update OllamaModels.swift**
   ```swift
   struct MyNewRequest: Codable {
       let model: String
       let input: String
   }

   struct MyNewResponse: Codable {
       let output: String
   }
   ```

2. **Update OllamaClient.swift**
   ```swift
   public func myNewEndpoint(input: String) async throws -> String {
       let requestBody = MyNewRequest(model: model, input: input)

       let response = try await post(
           endpoint: "/api/my-endpoint",
           body: requestBody,
           responseType: MyNewResponse.self
       )

       return response.output
   }
   ```

## Testing

### Running Tests

```bash
# All tests
swift test

# Specific test
swift test --filter OllamaClientTests

# With coverage (if available)
swift test --enable-code-coverage
```

### Writing Tests

```swift
import XCTest
@testable import AIShellCore

final class MyFeatureTests: XCTestCase {
    var client: OllamaClient!

    override func setUp() async throws {
        client = OllamaClient()

        // Skip if Ollama not available
        let isHealthy = await client.healthCheck()
        try XCTSkipUnless(isHealthy, "Ollama not available")
    }

    func testMyFeature() async throws {
        let result = try await client.myFeature(input: "test")
        XCTAssertFalse(result.isEmpty)
    }
}
```

### Integration Testing

```bash
# Build and install in debug mode
./install.sh --debug

# Start daemon manually
ai-shell-daemon --verbose

# In another terminal, test commands
ai_shell_health
ai_shell_task "test task"
```

## Documentation

### Code Documentation

Use Swift's documentation comments:

```swift
/// Brief description
///
/// Detailed description of what this does,
/// including any important behavior or side effects.
///
/// - Parameters:
///   - param1: Description of param1
///   - param2: Description of param2
/// - Returns: Description of return value
/// - Throws: Description of errors that can be thrown
public func myFunction(param1: String, param2: Int) throws -> Bool {
    // Implementation
}
```

### Updating Documentation

When making changes:
- Update README.md for user-facing changes
- Update ARCHITECTURE.md for architectural changes
- Update CONFIGURATION.md for config changes
- Add examples to demonstrate usage

## Release Process

1. **Update version** in relevant files
2. **Update CHANGELOG.md** with changes
3. **Run full test suite**
4. **Build release binary**
5. **Tag release** with `git tag v1.2.3`
6. **Push tag** with `git push --tags`
7. **Create GitHub release** with notes

## Getting Help

- **Questions:** Open a discussion on GitHub
- **Bugs:** Create an issue
- **Chat:** Join our community (if available)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.

---

**Thank you for contributing to AI Shell Assistant!**

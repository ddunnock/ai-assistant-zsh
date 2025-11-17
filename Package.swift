// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AIShellDaemon",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "ai-shell-daemon",
            targets: ["AIShellDaemon"]
        ),
        .library(
            name: "AIShellCore",
            targets: ["AIShellCore"]
        ),
    ],
    dependencies: [
        // Async HTTP client for Ollama communication
        .package(
            url: "https://github.com/swift-server/async-http-client.git",
            from: "1.19.0"
        ),
        // Logging
        .package(
            url: "https://github.com/apple/swift-log.git",
            from: "1.5.0"
        ),
        // Command line argument parsing
        .package(
            url: "https://github.com/apple/swift-argument-parser.git",
            from: "1.2.0"
        ),
        // Cryptography for cache keys (SHA256)
        .package(
            url: "https://github.com/apple/swift-crypto.git",
            from: "3.0.0"
        ),
    ],
    targets: [
        // Main executable
        .executableTarget(
            name: "AIShellDaemon",
            dependencies: [
                "AIShellCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Logging", package: "swift-log"),
            ],
            path: "Sources/AIShellDaemon"
        ),
        
        // Core library
        .target(
            name: "AIShellCore",
            dependencies: [
                .product(name: "AsyncHTTPClient", package: "async-http-client"),
                .product(name: "Logging", package: "swift-log"),
                .product(name: "Crypto", package: "swift-crypto"),
            ],
            path: "Sources/AIShellCore"
        ),
        
        // Tests
        .testTarget(
            name: "AIShellTests",
            dependencies: ["AIShellCore"],
            path: "Tests/AIShellTests"
        ),
    ]
)

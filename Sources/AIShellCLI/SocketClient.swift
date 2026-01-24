import Foundation
import AIShellCore

/// Client for communicating with the AI Shell daemon via Unix socket
struct SocketClient {

    let socketPath: String

    init(socketPath: String = DaemonManager.socketPath) {
        self.socketPath = socketPath
    }

    // MARK: - Errors

    enum ClientError: Error, LocalizedError {
        case connectionFailed
        case sendFailed
        case receiveFailed
        case invalidResponse
        case requestFailed(String)
        case timeout

        var errorDescription: String? {
            switch self {
            case .connectionFailed:
                return "Failed to connect to daemon socket"
            case .sendFailed:
                return "Failed to send request to daemon"
            case .receiveFailed:
                return "Failed to receive response from daemon"
            case .invalidResponse:
                return "Received invalid response from daemon"
            case .requestFailed(let message):
                return "Request failed: \(message)"
            case .timeout:
                return "Request timed out"
            }
        }
    }

    // MARK: - Low-level Socket Communication

    private func connect() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ClientError.connectionFailed
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        _ = withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 104) { dest in
                pathBytes.withUnsafeBufferPointer { src in
                    memcpy(dest, src.baseAddress!, min(src.count, 104))
                }
            }
        }

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard result == 0 else {
            close(fd)
            throw ClientError.connectionFailed
        }

        return fd
    }

    private func send(fd: Int32, data: Data) throws {
        // Send 4-byte length prefix (big endian)
        var length = UInt32(data.count).bigEndian
        let lengthResult = withUnsafeBytes(of: &length) { ptr in
            Darwin.send(fd, ptr.baseAddress!, 4, 0)
        }
        guard lengthResult == 4 else {
            throw ClientError.sendFailed
        }

        // Send payload
        let payloadResult = data.withUnsafeBytes { ptr in
            Darwin.send(fd, ptr.baseAddress!, data.count, 0)
        }
        guard payloadResult == data.count else {
            throw ClientError.sendFailed
        }
    }

    private func receive(fd: Int32) throws -> Data {
        // Read 4-byte length prefix
        var lengthBytes = [UInt8](repeating: 0, count: 4)
        let lengthResult = Darwin.recv(fd, &lengthBytes, 4, 0)
        guard lengthResult == 4 else {
            throw ClientError.receiveFailed
        }

        let length = Data(lengthBytes).withUnsafeBytes { ptr in
            ptr.load(as: UInt32.self).bigEndian
        }

        guard length > 0 && length < 10_000_000 else {
            throw ClientError.invalidResponse
        }

        // Read payload
        var payload = Data(count: Int(length))
        var totalRead = 0
        while totalRead < Int(length) {
            let remaining = Int(length) - totalRead
            let result = payload.withUnsafeMutableBytes { ptr in
                Darwin.recv(fd, ptr.baseAddress!.advanced(by: totalRead), remaining, 0)
            }
            guard result > 0 else {
                throw ClientError.receiveFailed
            }
            totalRead += result
        }

        return payload
    }

    // MARK: - Request Building

    private func createRequest(type: String, payload: [String: Any]) -> Data? {
        let request: [String: Any] = [
            "id": "cli-\(UUID().uuidString)",
            "type": type,
            "payload": payload,
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        return try? JSONSerialization.data(withJSONObject: request)
    }

    private func parseResponse(_ data: Data) throws -> Response {
        let decoder = JSONDecoder()
        // Use custom date decoding to handle various ISO8601 formats
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)

            // Try standard ISO8601
            let iso8601Formatter = ISO8601DateFormatter()
            iso8601Formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Try without fractional seconds
            iso8601Formatter.formatOptions = [.withInternetDateTime]
            if let date = iso8601Formatter.date(from: dateString) {
                return date
            }

            // Fallback to current date if parsing fails
            return Date()
        }
        return try decoder.decode(Response.self, from: data)
    }

    // MARK: - High-level API

    /// Send a health check request
    func sendHealthRequest() async throws -> Response {
        let fd = try connect()
        defer { close(fd) }

        guard let requestData = createRequest(type: "health", payload: [:]) else {
            throw ClientError.sendFailed
        }

        try send(fd: fd, data: requestData)
        let responseData = try receive(fd: fd)
        return try parseResponse(responseData)
    }

    /// Send a suggest request
    func sendSuggestRequest(
        command: String,
        workingDirectory: String? = nil,
        context: RequestContext? = nil
    ) async throws -> Response {
        let fd = try connect()
        defer { close(fd) }

        var payload: [String: Any] = [
            "command": command,
            "workingDirectory": workingDirectory ?? FileManager.default.currentDirectoryPath
        ]

        if let context = context {
            payload["context"] = contextToDictionary(context)
        }

        guard let requestData = createRequest(type: "suggest", payload: payload) else {
            throw ClientError.sendFailed
        }

        try send(fd: fd, data: requestData)
        let responseData = try receive(fd: fd)
        return try parseResponse(responseData)
    }

    /// Send an explain request
    func sendExplainRequest(
        command: String,
        workingDirectory: String? = nil,
        context: RequestContext? = nil
    ) async throws -> Response {
        let fd = try connect()
        defer { close(fd) }

        var payload: [String: Any] = [
            "command": command,
            "workingDirectory": workingDirectory ?? FileManager.default.currentDirectoryPath
        ]

        if let context = context {
            payload["context"] = contextToDictionary(context)
        }

        guard let requestData = createRequest(type: "explain", payload: payload) else {
            throw ClientError.sendFailed
        }

        try send(fd: fd, data: requestData)
        let responseData = try receive(fd: fd)
        return try parseResponse(responseData)
    }

    /// Send a task request
    func sendTaskRequest(
        task: String,
        workingDirectory: String? = nil,
        context: RequestContext? = nil
    ) async throws -> Response {
        let fd = try connect()
        defer { close(fd) }

        var payload: [String: Any] = [
            "task": task,
            "workingDirectory": workingDirectory ?? FileManager.default.currentDirectoryPath
        ]

        if let context = context {
            payload["context"] = contextToDictionary(context)
        }

        guard let requestData = createRequest(type: "task", payload: payload) else {
            throw ClientError.sendFailed
        }

        try send(fd: fd, data: requestData)
        let responseData = try receive(fd: fd)
        return try parseResponse(responseData)
    }

    // MARK: - Helpers

    private func contextToDictionary(_ context: RequestContext) -> [String: Any] {
        var dict: [String: Any] = [:]

        if let history = context.history {
            dict["history"] = history
        }
        if let gitBranch = context.gitBranch {
            dict["gitBranch"] = gitBranch
        }
        if let environment = context.environment {
            dict["environment"] = environment
        }

        return dict
    }

    /// Build context from current shell environment
    static func buildContext() -> RequestContext {
        var context = RequestContext()

        // Get git branch if in a repo
        let gitProcess = Process()
        gitProcess.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        gitProcess.arguments = ["symbolic-ref", "--short", "HEAD"]
        gitProcess.currentDirectoryURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)

        let pipe = Pipe()
        gitProcess.standardOutput = pipe
        gitProcess.standardError = FileHandle.nullDevice

        try? gitProcess.run()
        gitProcess.waitUntilExit()

        if gitProcess.terminationStatus == 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            context.gitBranch = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Get environment
        context.environment = [
            "SHELL": ProcessInfo.processInfo.environment["SHELL"] ?? "",
            "USER": ProcessInfo.processInfo.environment["USER"] ?? "",
            "PWD": FileManager.default.currentDirectoryPath
        ]

        return context
    }
}

// MARK: - Request Context

struct RequestContext {
    var history: [String]?
    var gitBranch: String?
    var environment: [String: String]?
}

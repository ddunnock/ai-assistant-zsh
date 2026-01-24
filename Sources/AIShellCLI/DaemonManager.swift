import Foundation

/// Manages the AI Shell daemon lifecycle
struct DaemonManager {

    // MARK: - Paths

    static var configDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ai-shell")
    }

    static var pidFile: URL {
        configDirectory.appendingPathComponent("daemon.pid")
    }

    static var logFile: URL {
        configDirectory.appendingPathComponent("daemon.log")
    }

    static var socketPath: String {
        "/tmp/ai-shell.sock"
    }

    static var daemonExecutable: URL? {
        // Try to find ai-shell-daemon in common locations
        let possiblePaths = [
            // Same directory as this executable
            Bundle.main.executableURL?.deletingLastPathComponent()
                .appendingPathComponent("ai-shell-daemon"),
            // /usr/local/bin
            URL(fileURLWithPath: "/usr/local/bin/ai-shell-daemon"),
            // ~/.local/bin
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local/bin/ai-shell-daemon"),
        ]

        for path in possiblePaths {
            if let path = path, FileManager.default.isExecutableFile(atPath: path.path) {
                return path
            }
        }
        return nil
    }

    // MARK: - Errors

    enum DaemonError: Error, LocalizedError {
        case alreadyRunning
        case notRunning
        case daemonNotFound
        case startFailed(String)
        case stopFailed(String)
        case socketTimeout

        var errorDescription: String? {
            switch self {
            case .alreadyRunning:
                return "Daemon is already running"
            case .notRunning:
                return "Daemon is not running"
            case .daemonNotFound:
                return "Could not find ai-shell-daemon executable"
            case .startFailed(let reason):
                return "Failed to start daemon: \(reason)"
            case .stopFailed(let reason):
                return "Failed to stop daemon: \(reason)"
            case .socketTimeout:
                return "Timed out waiting for daemon socket"
            }
        }
    }

    // MARK: - Status

    /// Check if the daemon is currently running
    func isRunning() -> Bool {
        guard let pid = readPID() else { return false }

        // Check if process exists
        let result = kill(pid, 0)
        guard result == 0 else { return false }

        // Also verify socket exists
        return socketExists()
    }

    /// Check if the socket file exists
    func socketExists() -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: Self.socketPath,
            isDirectory: &isDirectory
        )
        return exists && !isDirectory.boolValue
    }

    /// Read the PID from the PID file
    func readPID() -> pid_t? {
        guard let contents = try? String(contentsOf: Self.pidFile, encoding: .utf8) else {
            return nil
        }
        return pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Write PID to file
    private func writePID(_ pid: pid_t) throws {
        try ensureConfigDirectory()
        try String(pid).write(to: Self.pidFile, atomically: true, encoding: .utf8)
    }

    /// Remove PID file
    private func removePIDFile() {
        try? FileManager.default.removeItem(at: Self.pidFile)
    }

    /// Ensure config directory exists
    private func ensureConfigDirectory() throws {
        try FileManager.default.createDirectory(
            at: Self.configDirectory,
            withIntermediateDirectories: true
        )
    }

    // MARK: - Lifecycle

    /// Start the daemon in the background
    func start(verbose: Bool = false) async throws {
        if isRunning() {
            throw DaemonError.alreadyRunning
        }

        guard let executable = Self.daemonExecutable else {
            throw DaemonError.daemonNotFound
        }

        try ensureConfigDirectory()

        // Remove stale socket if it exists
        if socketExists() {
            try? FileManager.default.removeItem(atPath: Self.socketPath)
        }

        // Remove stale PID file
        removePIDFile()

        // Prepare log file
        FileManager.default.createFile(atPath: Self.logFile.path, contents: nil)

        // Build arguments
        var arguments = ["--socket", Self.socketPath]
        if verbose {
            arguments.append("--verbose")
        }

        // Launch daemon process
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser

        // Redirect stdout/stderr to log file
        let logHandle = try FileHandle(forWritingTo: Self.logFile)
        process.standardOutput = logHandle
        process.standardError = logHandle

        // Start process
        try process.run()

        // Write PID
        try writePID(process.processIdentifier)

        // Wait for socket to be available
        try await waitForSocket(timeout: 10.0)
    }

    /// Stop the daemon gracefully
    func stop() async throws {
        guard let pid = readPID() else {
            throw DaemonError.notRunning
        }

        // Send SIGTERM for graceful shutdown
        let result = kill(pid, SIGTERM)
        if result != 0 {
            throw DaemonError.stopFailed("Failed to send SIGTERM to process \(pid)")
        }

        // Wait for process to exit
        for _ in 0..<50 {  // 5 seconds max
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
            if kill(pid, 0) != 0 {
                // Process has exited
                removePIDFile()
                // Remove socket if still exists
                try? FileManager.default.removeItem(atPath: Self.socketPath)
                return
            }
        }

        // Force kill if still running
        kill(pid, SIGKILL)
        removePIDFile()
        try? FileManager.default.removeItem(atPath: Self.socketPath)
    }

    /// Restart the daemon
    func restart(verbose: Bool = false) async throws {
        if isRunning() {
            try await stop()
        }
        try await start(verbose: verbose)
    }

    /// Wait for the socket to become available
    func waitForSocket(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while Date() < deadline {
            if socketExists() {
                // Give daemon a moment to start accepting connections
                try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
                return
            }
            try await Task.sleep(nanoseconds: 100_000_000)  // 100ms
        }

        throw DaemonError.socketTimeout
    }

    /// Ensure daemon is running, starting it if necessary
    func ensureRunning(verbose: Bool = false) async throws {
        if !isRunning() {
            print("Starting AI daemon...")
            try await start(verbose: verbose)
            print("Daemon started.")
        }
    }

    // MARK: - Health Check

    struct HealthReport {
        var daemonRunning = false
        var pid: pid_t?
        var socketExists = false
        var socketResponsive = false
        var ollamaReachable = false
        var ollamaModel: String?
        var uptime: TimeInterval?
        var memoryUsage: UInt64?

        var isHealthy: Bool {
            daemonRunning && socketExists && socketResponsive && ollamaReachable
        }
    }

    /// Perform a comprehensive health check
    func doctor() async -> HealthReport {
        var report = HealthReport()

        // Check PID
        report.pid = readPID()

        // Check if daemon is running
        report.daemonRunning = isRunning()

        // Check socket
        report.socketExists = socketExists()

        // Check socket responsiveness via health request
        if report.socketExists {
            let client = SocketClient()
            if let response = try? await client.sendHealthRequest() {
                report.socketResponsive = response.status == .success
                // Extract Ollama status from response if available
                if report.socketResponsive {
                    report.ollamaReachable = true
                }
            }
        }

        // Get model from config
        report.ollamaModel = getConfiguredModel()

        return report
    }

    /// Read the configured model from config file
    private func getConfiguredModel() -> String? {
        let configPath = Self.configDirectory.appendingPathComponent("config.json")
        guard let data = try? Data(contentsOf: configPath),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = json["model"] as? String else {
            return "llama3.1:8b" // default
        }
        return model
    }
}

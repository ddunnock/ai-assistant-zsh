// Sources/AIShellDaemon/main.swift

@main
enum Main {
    static func main() async throws {
        try await AIShellDaemonCLI.main()
    }
}

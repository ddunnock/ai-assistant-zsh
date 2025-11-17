// Sources/AIShellCore/Server/SocketServer.swift

import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Unix domain socket server using BSD sockets
public actor SocketServer {
    private let socketPath: String
    private var socketFD: Int32?
    private let requestHandler: any RequestHandling
    private let logger = LoggerFactory.create(category: "socket")

    private var connections: Set<Connection> = []
    private var isRunning = false
    private var acceptTask: Task<Void, Never>?

    public init(socketPath: String, requestHandler: any RequestHandling) {
        self.socketPath = socketPath
        self.requestHandler = requestHandler
    }

    // MARK: - Public API

    public func start() async throws {
        guard !isRunning else {
            logger.warning("Server already running")
            return
        }

        // Remove existing socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        // Create parent directory if needed
        let socketDir = (socketPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(
            atPath: socketDir,
            withIntermediateDirectories: true
        )

        // Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw AIShellError.socketError("Failed to create socket: \(String(cString: strerror(errno)))")
        }

        // Set socket to non-blocking
        var flags = fcntl(fd, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(fd, F_SETFL, flags)

        // Bind socket
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        guard socketPath.count < MemoryLayout.size(ofValue: addr.sun_path) else {
            Darwin.close(fd)
            throw AIShellError.socketError("Socket path too long")
        }

        _ = withUnsafeMutablePointer(to: &addr.sun_path.0) { ptr in
            socketPath.withCString { cString in
                strcpy(ptr, cString)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.bind(fd, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }

        guard bindResult >= 0 else {
            Darwin.close(fd)
            throw AIShellError.socketError("Failed to bind socket: \(String(cString: strerror(errno)))")
        }

        // Listen
        guard listen(fd, 128) >= 0 else {
            Darwin.close(fd)
            try? FileManager.default.removeItem(atPath: socketPath)
            throw AIShellError.socketError("Failed to listen on socket: \(String(cString: strerror(errno)))")
        }

        // Set permissions
        chmod(socketPath, 0o600)

        socketFD = fd
        isRunning = true

        logger.info("Socket server started", metadata: ["path": socketPath])

        // Start accepting connections
        acceptTask = Task {
            await acceptConnections()
        }
    }

    public func stop() async {
        guard isRunning else { return }

        logger.info("Stopping socket server")

        isRunning = false
        acceptTask?.cancel()
        acceptTask = nil

        // Close all connections
        for connection in connections {
            await connection.close()
        }
        connections.removeAll()

        // Close socket
        if let fd = socketFD {
            Darwin.close(fd)
            socketFD = nil
        }

        // Remove socket file
        try? FileManager.default.removeItem(atPath: socketPath)

        logger.info("Socket server stopped")
    }

    // MARK: - Connection Management

    private func acceptConnections() async {
        guard let fd = socketFD else { return }

        while isRunning {
            do {
                // Try to accept a connection
                let clientFD = accept(fd, nil, nil)

                if clientFD >= 0 {
                    let connection = Connection(
                        socketFD: clientFD,
                        requestHandler: requestHandler,
                        logger: logger
                    )

                    connections.insert(connection)

                    logger.debug("New connection", metadata: [
                        "total": String(connections.count)
                    ])

                    Task {
                        await connection.start()
                        await removeConnection(connection)
                    }
                } else if errno == EAGAIN || errno == EWOULDBLOCK {
                    // No connections available, wait a bit
                    try? await Task.sleep(nanoseconds: 10_000_000) // 10ms
                } else {
                    logger.error("Accept failed: \(String(cString: strerror(errno)))")
                    try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
                }
            } catch {
                if isRunning {
                    logger.error("Accept loop error", metadata: ["error": error.localizedDescription])
                }
            }
        }
    }

    private func removeConnection(_ connection: Connection) {
        connections.remove(connection)
        logger.debug("Connection removed", metadata: [
            "total": String(connections.count)
        ])
    }
}

// MARK: - Connection

private final class Connection: Hashable, @unchecked Sendable {
    let id = UUID()
    private let socketFD: Int32
    private let requestHandler: any RequestHandling
    private let logger: AppLogger
    private var isActive = true

    init(
        socketFD: Int32,
        requestHandler: any RequestHandling,
        logger: AppLogger
    ) {
        self.socketFD = socketFD
        self.requestHandler = requestHandler
        self.logger = logger

        // Set socket to non-blocking
        var flags = fcntl(socketFD, F_GETFL, 0)
        flags |= O_NONBLOCK
        _ = fcntl(socketFD, F_SETFL, flags)
    }

    func start() async {
        while isActive {
            do {
                // Read length prefix (4 bytes)
                guard let lengthData = try await readExactly(bytes: 4) else {
                    break
                }

                let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian

                // Read message
                guard let messageData = try await readExactly(bytes: Int(length)) else {
                    break
                }

                // Process message
                await processMessage(messageData)
            } catch {
                logger.error("Connection error", metadata: ["error": error.localizedDescription])
                break
            }
        }

        await close()
    }

    func close() async {
        guard isActive else { return }
        isActive = false
        Darwin.close(socketFD)
    }

    private func readExactly(bytes: Int) async throws -> Data? {
        var buffer = Data(count: bytes)
        var totalRead = 0

        while totalRead < bytes && isActive {
            let result = buffer.withUnsafeMutableBytes { ptr in
                Darwin.read(socketFD, ptr.baseAddress! + totalRead, bytes - totalRead)
            }

            if result > 0 {
                totalRead += result
            } else if result == 0 {
                // Connection closed
                return nil
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // Would block, wait and retry
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            } else {
                // Error
                throw AIShellError.socketError("Read failed: \(String(cString: strerror(errno)))")
            }
        }

        return totalRead == bytes ? buffer : nil
    }

    private func writeAll(_ data: Data) async throws {
        var totalWritten = 0
        let count = data.count

        while totalWritten < count && isActive {
            let result = data.withUnsafeBytes { ptr in
                Darwin.write(socketFD, ptr.baseAddress! + totalWritten, count - totalWritten)
            }

            if result > 0 {
                totalWritten += result
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                // Would block, wait and retry
                try? await Task.sleep(nanoseconds: 1_000_000) // 1ms
            } else {
                throw AIShellError.socketError("Write failed: \(String(cString: strerror(errno)))")
            }
        }
    }

    private func processMessage(_ data: Data) async {
        do {
            let request = try JSONDecoder().decode(Request.self, from: data)

            logger.debug("Processing request", metadata: [
                "id": request.id,
                "type": request.type.rawValue
            ])

            let response = await requestHandler.handle(request)
            let responseData = try JSONEncoder().encode(response)

            // Frame the response
            let framedMessage = FramedMessage(data: responseData)
            let encodedData = framedMessage.encoded()

            // Send response
            try await writeAll(encodedData)

            logger.debug("Response sent", metadata: [
                "request_id": request.id
            ])
        } catch {
            logger.error("Message processing error", metadata: ["error": error.localizedDescription])

            // Try to send error response
            let errorResponse = Response.error(
                requestId: UUID().uuidString,
                code: "PROCESSING_ERROR",
                message: error.localizedDescription
            )

            if let errorData = try? JSONEncoder().encode(errorResponse) {
                let framedMessage = FramedMessage(data: errorData)
                try? await writeAll(framedMessage.encoded())
            }
        }
    }

    // MARK: - Hashable

    static func == (lhs: Connection, rhs: Connection) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

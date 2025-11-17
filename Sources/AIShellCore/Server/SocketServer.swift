// Sources/AIShellCore/Server/SocketServer.swift

import Foundation
import Network

/// Unix domain socket server
public actor SocketServer {
    private let socketPath: String
    private var listener: NWListener?
    private let requestHandler: any RequestHandling
    private let logger = LoggerFactory.create(category: "socket")

    private var connections: Set<Connection> = []
    private var isRunning = false

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
        
        // Create listener with Unix domain socket parameters
        let parameters = NWParameters.unix

        listener = try NWListener(using: parameters, on: .unix(path: socketPath))
        
        listener?.newConnectionHandler = { [weak self] nwConnection in
            guard let self = self else { return }
            Task {
                await self.handleNewConnection(nwConnection)
            }
        }
        
        listener?.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task {
                await self.handleListenerStateChange(state)
            }
        }

        listener?.start(queue: .main)
        isRunning = true
    }
    
    public func stop() async {
        guard isRunning else { return }
        
        logger.info("Stopping socket server")
        
        // Cancel listener
        listener?.cancel()
        listener = nil
        
        // Close all connections
        for connection in connections {
            connection.close()
        }
        connections.removeAll()
        
        // Remove socket file
        try? FileManager.default.removeItem(atPath: socketPath)
        
        isRunning = false
        logger.info("Socket server stopped")
    }
    
    // MARK: - Connection Management
    
    private func handleNewConnection(_ nwConnection: NWConnection) {
        let connection = Connection(
            nwConnection: nwConnection,
            requestHandler: requestHandler,
            logger: logger
        )
        
        connections.insert(connection)
        
        logger.debug("New connection", metadata: [
            "total": String(connections.count)
        ])
        
        connection.start { [weak self] in
            guard let self = self else { return }
            Task {
                await self.removeConnection(connection)
            }
        }
    }
    
    private func removeConnection(_ connection: Connection) {
        connections.remove(connection)
        logger.debug("Connection removed", metadata: [
            "total": String(connections.count)
        ])
    }
    
    private func handleListenerStateChange(_ state: NWListener.State) {
        switch state {
        case .ready:
            // Socket file now exists, set permissions (owner only)
            do {
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o600],
                    ofItemAtPath: socketPath
                )
                logger.info("Socket server ready", metadata: ["path": socketPath])
            } catch {
                logger.warning("Failed to set socket permissions", error: error)
                logger.info("Listener ready", metadata: ["path": socketPath])
            }
        case .failed(let error):
            logger.error("Listener failed", error: error)
            Task {
                await stop()
            }
        case .cancelled:
            logger.info("Listener cancelled")
        default:
            break
        }
    }
}

// MARK: - Connection

private final class Connection: Hashable, @unchecked Sendable {
    let id = UUID()
    private let nwConnection: NWConnection
    private let requestHandler: any RequestHandling
    private let logger: AppLogger
    private var completionHandler: (() -> Void)?

    init(
        nwConnection: NWConnection,
        requestHandler: any RequestHandling,
        logger: AppLogger
    ) {
        self.nwConnection = nwConnection
        self.requestHandler = requestHandler
        self.logger = logger
    }
    
    func start(onComplete: @escaping () -> Void) {
        self.completionHandler = onComplete
        
        nwConnection.stateUpdateHandler = { [weak self] state in
            self?.handleStateChange(state)
        }
        
        nwConnection.start(queue: .global())
        receiveMessage()
    }
    
    func close() {
        nwConnection.cancel()
    }
    
    private func handleStateChange(_ state: NWConnection.State) {
        switch state {
        case .ready:
            logger.debug("Connection ready", metadata: ["id": id.uuidString])
        case .failed(let error):
            logger.error("Connection failed", error: error)
            completionHandler?()
        case .cancelled:
            completionHandler?()
        default:
            break
        }
    }
    
    private func receiveMessage() {
        // First, receive the 4-byte length prefix
        nwConnection.receive(
            minimumIncompleteLength: 4,
            maximumLength: 4
        ) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let error = error {
                self.logger.error("Receive error", error: error)
                self.completionHandler?()
                return
            }
            
            guard let lengthData = data, lengthData.count == 4 else {
                self.logger.error("Invalid length prefix")
                self.completionHandler?()
                return
            }
            
            let length = lengthData.withUnsafeBytes { $0.load(as: UInt32.self) }.bigEndian
            
            // Now receive the message body
            self.nwConnection.receive(
                minimumIncompleteLength: Int(length),
                maximumLength: Int(length)
            ) { messageData, _, _, error in
                if let error = error {
                    self.logger.error("Message receive error", error: error)
                    self.completionHandler?()
                    return
                }
                
                guard let messageData = messageData else {
                    self.logger.error("Empty message data")
                    self.completionHandler?()
                    return
                }
                
                Task {
                    await self.processMessage(messageData)
                }
            }
            
            if !isComplete {
                self.receiveMessage()
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
            nwConnection.send(
                content: encodedData,
                completion: .contentProcessed { [weak self] error in
                    if let error = error {
                        self?.logger.error("Send error", error: error)
                    } else {
                        self?.logger.debug("Response sent", metadata: [
                            "request_id": request.id
                        ])
                    }
                }
            )
        } catch {
            logger.error("Message processing error", error: error)
            
            // Try to send error response
            let errorResponse = Response.error(
                requestId: UUID().uuidString,
                code: "PROCESSING_ERROR",
                message: error.localizedDescription
            )
            
            if let errorData = try? JSONEncoder().encode(errorResponse) {
                let framedMessage = FramedMessage(data: errorData)
                nwConnection.send(
                    content: framedMessage.encoded(),
                    completion: .contentProcessed { _ in }
                )
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
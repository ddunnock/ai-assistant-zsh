// Sources/AIShellCore/Server/RequestHandling.swift

import Foundation

/// Protocol for request handlers
public protocol RequestHandling: Actor {
    /// Handle a request and return a response
    func handle(_ request: Request) async -> Response
}

// Conform existing RequestHandler
extension RequestHandler: RequestHandling {}

// Conform EnhancedRequestHandler
extension EnhancedRequestHandler: RequestHandling {}

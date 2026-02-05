/**
 Transport interface for MCP (Model Context Protocol) communication.

 Port of `packages/mcp/src/tool/mcp-transport.ts`.
 Upstream commit: f3a72bc2a

 This module defines the base transport protocol for MCP communication and provides
 factory functions for creating transport instances.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - MCPTransport Protocol

/**
 Transport interface for MCP (Model Context Protocol) communication.
 Maps to the `Transport` interface in the MCP spec.
 */
public protocol MCPTransport: Sendable {
    /**
     Initialize and start the transport
     */
    func start() async throws

    /**
     Send a JSON-RPC message through the transport
     - Parameter message: The JSON-RPC message to send
     */
    func send(message: JSONRPCMessage) async throws

    /**
     Clean up and close the transport
     */
    func close() async throws

    /**
     Event handler for transport closure
     */
    var onclose: (@Sendable () -> Void)? { get set }

    /**
     Event handler for transport errors
     */
    var onerror: (@Sendable (Error) -> Void)? { get set }

    /**
     Event handler for received messages
     */
    var onmessage: (@Sendable (JSONRPCMessage) -> Void)? { get set }
}

// MARK: - MCPTransportConfig

/// Configuration for creating MCP transports
public struct MCPTransportConfig: Sendable {
    /// Transport type (`sse` or `http`)
    public let type: String

    /// The URL of the MCP server
    public let url: String

    /// Additional HTTP headers to be sent with requests
    public let headers: [String: String]?

    /// Optional OAuth client provider for authentication.
    public let authProvider: OAuthClientProvider?

    public init(
        type: String = "sse",
        url: String,
        headers: [String: String]? = nil,
        authProvider: OAuthClientProvider? = nil
    ) {
        self.type = type
        self.url = url
        self.headers = headers
        self.authProvider = authProvider
    }
}

// MARK: - Factory Functions

/**
 Create an MCP transport from configuration.

 - Parameter config: Transport configuration
 - Returns: An MCPTransport instance
 - Throws: MCPClientError if the transport type is unsupported

 - Note: SSE transport requires macOS 12.0+
 */
@available(macOS 12.0, iOS 15.0, watchOS 8.0, tvOS 15.0, *)
public func createMcpTransport(config: MCPTransportConfig) throws -> MCPTransport {
    switch config.type {
    case "sse":
        return try SseMCPTransport(config: config)

    case "http":
        return try HttpMCPTransport(config: config)

    default:
        throw MCPClientError(
            message: "Unsupported or invalid transport configuration. If you are using a custom transport, make sure it implements the MCPTransport interface."
        )
    }
}

/**
 Check if a value is a custom MCP transport instance (vs a config object).

 - Parameter value: The value to check
 - Returns: true if the value is an MCPTransport instance
 */
public func isCustomMcpTransport(_ value: Any) -> Bool {
    return value is MCPTransport
}

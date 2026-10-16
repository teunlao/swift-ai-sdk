/**
 Transport interface for MCP (Model Context Protocol) communication.

 Port of `packages/mcp/src/tool/mcp-transport.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4

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
    func send(message: JSONRPCMessage, options: MCPTransportSendOptions?) async throws

    /**
     Clean up and close the transport
     */
    func close() async throws
    func close(options: MCPTransportCloseOptions?) async throws

    func setProtocolVersion(_ version: String)

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

public struct MCPTransportCloseOptions: Sendable {
    public let signal: (@Sendable () -> Bool)?
    public init(signal: (@Sendable () -> Bool)? = nil) { self.signal = signal }
}

public struct MCPTransportSendOptions: Sendable {
    public let signal: (@Sendable () -> Bool)?
    public let relatedRequestId: JSONRPCID?
    public let resumptionToken: String?
    public let onresumptiontoken: (@Sendable (String) -> Void)?

    public init(
        signal: (@Sendable () -> Bool)? = nil,
        relatedRequestId: JSONRPCID? = nil,
        resumptionToken: String? = nil,
        onresumptiontoken: (@Sendable (String) -> Void)? = nil
    ) {
        self.signal = signal
        self.relatedRequestId = relatedRequestId
        self.resumptionToken = resumptionToken
        self.onresumptiontoken = onresumptiontoken
    }
}

public extension MCPTransport {
    func setProtocolVersion(_ version: String) {}
    func close(options: MCPTransportCloseOptions?) async throws { try await close() }
    func send(message: JSONRPCMessage, options: MCPTransportSendOptions?) async throws {
        try await runMCPOperation(options: .init(signal: options?.signal)) {
            try await self.send(message: message)
        }
    }
}

public enum MCPRedirectMode: String, Sendable {
    case follow
    case error
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
    public let redirect: MCPRedirectMode
    public let fetch: FetchFunction?
    public let initialSessionId: String?
    public let initialProtocolVersion: String?
    public let onSessionIdChange: (@Sendable (String?) -> Void)?
    public let onSessionExpired: (@Sendable (String) -> Void)?
    public let terminateSessionOnClose: Bool

    public init(
        type: String = "sse",
        url: String,
        headers: [String: String]? = nil,
        authProvider: OAuthClientProvider? = nil,
        redirect: MCPRedirectMode = .error,
        initialSessionId: String? = nil,
        initialProtocolVersion: String? = nil,
        onSessionIdChange: (@Sendable (String?) -> Void)? = nil,
        onSessionExpired: (@Sendable (String) -> Void)? = nil,
        terminateSessionOnClose: Bool = true,
        fetch: FetchFunction? = nil
    ) {
        self.type = type
        self.url = url
        self.headers = headers
        self.authProvider = authProvider
        self.redirect = redirect
        self.fetch = fetch
        self.initialSessionId = initialSessionId
        self.initialProtocolVersion = initialProtocolVersion
        self.onSessionIdChange = onSessionIdChange
        self.onSessionExpired = onSessionExpired
        self.terminateSessionOnClose = terminateSessionOnClose
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

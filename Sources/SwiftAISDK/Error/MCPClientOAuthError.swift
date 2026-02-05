import Foundation
import AISDKProvider

/**
 Error types for MCP OAuth flows.

 Port of `packages/mcp/src/error/oauth-error.ts`.
 Upstream commit: f3a72bc2a
 */

/// Base marker error for OAuth-related failures inside the MCP client flow.
public struct MCPClientOAuthError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_MCPClientOAuthError"

    public let name: String
    public let message: String
    public let cause: (any Error)?

    public init(name: String = "MCPClientOAuthError", message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

/// OAuth error response: `server_error`.
public struct ServerError: AISDKError, @unchecked Sendable {
    public static let errorDomain = MCPClientOAuthError.errorDomain
    public static let errorCode = "server_error"

    public let name: String
    public let message: String
    public let cause: (any Error)?

    public init(name: String = "MCPClientOAuthError", message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

/// OAuth error response: `invalid_client`.
public struct InvalidClientError: AISDKError, @unchecked Sendable {
    public static let errorDomain = MCPClientOAuthError.errorDomain
    public static let errorCode = "invalid_client"

    public let name: String
    public let message: String
    public let cause: (any Error)?

    public init(name: String = "MCPClientOAuthError", message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

/// OAuth error response: `invalid_grant`.
public struct InvalidGrantError: AISDKError, @unchecked Sendable {
    public static let errorDomain = MCPClientOAuthError.errorDomain
    public static let errorCode = "invalid_grant"

    public let name: String
    public let message: String
    public let cause: (any Error)?

    public init(name: String = "MCPClientOAuthError", message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}

/// OAuth error response: `unauthorized_client`.
public struct UnauthorizedClientError: AISDKError, @unchecked Sendable {
    public static let errorDomain = MCPClientOAuthError.errorDomain
    public static let errorCode = "unauthorized_client"

    public let name: String
    public let message: String
    public let cause: (any Error)?

    public init(name: String = "MCPClientOAuthError", message: String, cause: (any Error)? = nil) {
        self.name = name
        self.message = message
        self.cause = cause
    }
}


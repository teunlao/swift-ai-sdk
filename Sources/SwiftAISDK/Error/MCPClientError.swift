import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when an error occurs with the MCP (Model Context Protocol) client.

 Port of `packages/mcp/src/error/mcp-client-error.ts`.
 */
public struct MCPClientError: AISDKError, @unchecked Sendable {
    public static let errorDomain = "vercel.ai.error.AI_MCPClientError"

    public let name: String
    public let message: String
    public let cause: (any Error)?

    /// Additional error data (marked @unchecked Sendable to match TypeScript's unknown)
    public let data: Any?

    /// Error code
    public let code: Int?
    public let statusCode: Int?
    public let url: String?
    public let responseBody: String?

    public init(
        name: String = "MCPClientError",
        message: String,
        cause: (any Error)? = nil,
        data: Any? = nil,
        code: Int? = nil,
        statusCode: Int? = nil,
        url: String? = nil,
        responseBody: String? = nil
    ) {
        self.name = name
        self.message = message
        self.cause = cause
        self.data = data
        self.code = code
        self.statusCode = statusCode
        self.url = url
        self.responseBody = responseBody
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

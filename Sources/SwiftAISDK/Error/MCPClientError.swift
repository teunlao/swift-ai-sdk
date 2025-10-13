import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Error thrown when an error occurs with the MCP (Model Context Protocol) client.

 Port of `@ai-sdk/ai/src/error/mcp-client-error.ts`.
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

    public init(
        name: String = "MCPClientError",
        message: String,
        cause: (any Error)? = nil,
        data: Any? = nil,
        code: Int? = nil
    ) {
        self.name = name
        self.message = message
        self.cause = cause
        self.data = data
        self.code = code
    }

    public static func isInstance(_ error: any Error) -> Bool {
        hasMarker(error, marker: errorDomain)
    }
}

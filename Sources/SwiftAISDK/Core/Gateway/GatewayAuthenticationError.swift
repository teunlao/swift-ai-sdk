import Foundation

/**
 Authentication failed - invalid API key or OIDC token.

 Port of `@ai-sdk/gateway/src/errors/gateway-authentication-error.ts`.

 Minimal implementation for `wrapGatewayError` support.
 */
public struct GatewayAuthenticationError: GatewayError, GatewayErrorMarker {
    public let name: String = "GatewayAuthenticationError"
    public let type: String = "authentication_error"
    public let statusCode: Int
    public let cause: Error?
    public let message: String

    public init(
        message: String = "Authentication failed",
        statusCode: Int = 401,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return error is GatewayAuthenticationError
    }
}

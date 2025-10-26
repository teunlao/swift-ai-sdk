import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-authentication-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Authentication failed - invalid API key or OIDC token.
public struct GatewayAuthenticationError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayAuthenticationError"
    public let type = "authentication_error"
    public let statusCode: Int
    public let message: String
    public let cause: Error?

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
        return Self.hasMarker(error) && error is GatewayAuthenticationError
    }

    /// Creates a contextual error message when authentication fails.
    public static func createContextualError(
        apiKeyProvided: Bool,
        oidcTokenProvided: Bool,
        message: String = "Authentication failed",
        statusCode: Int = 401,
        cause: Error? = nil
    ) -> GatewayAuthenticationError {
        let contextualMessage: String

        if apiKeyProvided {
            contextualMessage = """
AI Gateway authentication failed: Invalid API key.

Create a new API key: https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai%2Fapi-keys

Provide via 'apiKey' option or 'AI_GATEWAY_API_KEY' environment variable.
"""
        } else if oidcTokenProvided {
            contextualMessage = """
AI Gateway authentication failed: Invalid OIDC token.

Run 'npx vercel link' to link your project, then 'vc env pull' to fetch the token.

Alternatively, use an API key: https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai%2Fapi-keys
"""
        } else {
            contextualMessage = """
AI Gateway authentication failed: No authentication provided.

Option 1 - API key:
Create an API key: https://vercel.com/d?to=%2F%5Bteam%5D%2F%7E%2Fai%2Fapi-keys
Provide via 'apiKey' option or 'AI_GATEWAY_API_KEY' environment variable.

Option 2 - OIDC token:
Run 'npx vercel link' to link your project, then 'vc env pull' to fetch the token.
"""
        }

        return GatewayAuthenticationError(
            message: contextualMessage.isEmpty ? message : contextualMessage,
            statusCode: statusCode,
            cause: cause
        )
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-rate-limit-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Rate limit exceeded.
public struct GatewayRateLimitError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayRateLimitError"
    public let type = "rate_limit_exceeded"
    public let statusCode: Int
    public let message: String
    public let cause: Error?

    public init(
        message: String = "Rate limit exceeded",
        statusCode: Int = 429,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayRateLimitError
    }
}

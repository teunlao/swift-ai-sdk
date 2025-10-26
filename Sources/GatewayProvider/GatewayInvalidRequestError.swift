import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-invalid-request-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Invalid request - missing headers, malformed data, etc.
public struct GatewayInvalidRequestError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayInvalidRequestError"
    public let type = "invalid_request_error"
    public let statusCode: Int
    public let message: String
    public let cause: Error?

    public init(
        message: String = "Invalid request",
        statusCode: Int = 400,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayInvalidRequestError
    }
}

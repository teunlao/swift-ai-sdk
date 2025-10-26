import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-internal-server-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Internal server error from the Gateway.
public struct GatewayInternalServerError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayInternalServerError"
    public let type = "internal_server_error"
    public let statusCode: Int
    public let message: String
    public let cause: Error?

    public init(
        message: String = "Internal server error",
        statusCode: Int = 500,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayInternalServerError
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-internal-server-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Internal server error from the Gateway.
public struct GatewayInternalServerError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayInternalServerError"
    public let type = "internal_server_error"
    public let statusCode: Int
    public let message: String
    public let cause: Error?
    public let generationId: String?

    public init(
        message: String = "Internal server error",
        statusCode: Int = 500,
        cause: Error? = nil,
        generationId: String? = nil
    ) {
        self.generationId = generationId
        self.message = generationId.map { "\(message) [\($0)]" } ?? message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayInternalServerError
    }
}

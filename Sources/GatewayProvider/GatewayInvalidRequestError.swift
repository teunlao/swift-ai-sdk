import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-invalid-request-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Invalid request - missing headers, malformed data, etc.
public struct GatewayInvalidRequestError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayInvalidRequestError"
    public let type = "invalid_request_error"
    public let statusCode: Int
    public let message: String
    public let cause: Error?
    public let generationId: String?

    public init(
        message: String = "Invalid request",
        statusCode: Int = 400,
        cause: Error? = nil,
        generationId: String? = nil
    ) {
        self.generationId = generationId
        self.message = generationId.map { "\(message) [\($0)]" } ?? message
        self.statusCode = statusCode
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayInvalidRequestError
    }
}

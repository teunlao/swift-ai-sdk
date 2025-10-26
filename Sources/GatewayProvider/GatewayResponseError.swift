import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-response-error.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

/// Gateway response parsing error.
public struct GatewayResponseError: GatewayError, GatewayErrorMarker, @unchecked Sendable {
    public let name = "GatewayResponseError"
    public let type = "response_error"
    public let statusCode: Int
    public let message: String
    public let response: AnySendable?
    public let validationError: TypeValidationError?
    public let cause: Error?

    public init(
        message: String = "Invalid response from Gateway",
        statusCode: Int = 502,
        response: Any? = nil,
        validationError: TypeValidationError? = nil,
        cause: Error? = nil
    ) {
        self.message = message
        self.statusCode = statusCode
        self.response = response.map(AnySendable.init)
        self.validationError = validationError
        self.cause = cause
    }

    public static func isInstance(_ error: Any?) -> Bool {
        return Self.hasMarker(error) && error is GatewayResponseError
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/gateway-error.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

/// Base protocol for Gateway errors.
public protocol GatewayError: Error, Sendable {
    var name: String { get }
    var type: String { get }
    var statusCode: Int { get }
    var message: String { get }
    var cause: Error? { get }
    var generationId: String? { get }

    static func isInstance(_ error: Any?) -> Bool
    static func hasMarker(_ error: Any?) -> Bool
}

/// Internal marker protocol to support `hasMarker` checks.
protocol GatewayErrorMarker {}

public extension GatewayError {
    var generationId: String? { nil }

    static func hasMarker(_ error: Any?) -> Bool {
        return error is GatewayErrorMarker
    }
}

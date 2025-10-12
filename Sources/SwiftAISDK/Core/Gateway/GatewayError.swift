import Foundation

/**
 Base protocol for Gateway errors.

 Port of `@ai-sdk/gateway/src/errors/gateway-error.ts`.

 Gateway errors are thrown by the Vercel AI Gateway when requests fail.
 This is a minimal implementation to support `wrapGatewayError` function.
 Full Gateway package implementation is deferred to a later block.

 Swift adaptation: Uses protocol instead of abstract class for Swift idioms.
 */
public protocol GatewayError: Error {
    var name: String { get }
    var type: String { get }
    var statusCode: Int { get }
    var cause: Error? { get }
    var message: String { get }

    /// Check if an error is a Gateway error
    static func isInstance(_ error: Any?) -> Bool
}

// MARK: - Type marker

/// Internal marker protocol to identify Gateway errors via type system
protocol GatewayErrorMarker {}

extension GatewayError {
    public static func hasMarker(_ error: Any?) -> Bool {
        return error is GatewayErrorMarker
    }
}

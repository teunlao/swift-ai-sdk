import Foundation

/**
 * Protocol for AI SDK related errors.
 *
 * Swift equivalent of the TypeScript AISDKError class.
 * Uses errorDomain as an identifier similar to Symbol.for() in TypeScript.
 */
public protocol AISDKError: Error, LocalizedError, CustomStringConvertible {
    /// The domain identifier for this error type (equivalent to Symbol.for(marker) in TS)
    static var errorDomain: String { get }

    /// The name of the error
    var name: String { get }

    /// The error message
    var message: String { get }

    /// The underlying cause of the error, if any
    var cause: (any Error)? { get }
}

public extension AISDKError {
    /// Default implementation of LocalizedError
    var errorDescription: String? {
        message
    }

    /// Default implementation of CustomStringConvertible
    var description: String {
        var desc = "\(name): \(message)"
        if let cause = cause {
            desc += "\nCaused by: \(cause)"
        }
        return desc
    }
}

// MARK: - Free functions for error checking

/// Check if an error belongs to AI SDK error family
public func isAISDKError(_ error: any Error) -> Bool {
    error is any AISDKError
}

/// Check if an error has a specific domain marker
public func hasMarker(_ error: any Error, marker: String) -> Bool {
    guard let sdkError = error as? any AISDKError else {
        return false
    }
    return type(of: sdkError).errorDomain == marker
}

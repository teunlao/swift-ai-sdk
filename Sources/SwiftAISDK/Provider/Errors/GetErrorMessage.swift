import Foundation

/**
 * Extracts an error message from various error types.
 *
 * Swift port of `getErrorMessage` from TypeScript.
 * Handles String, Error, and other unknown types.
 */
public func getErrorMessage(_ error: (any Error)?) -> String {
    guard let error = error else {
        return "unknown error"
    }

    // If it's a LocalizedError, prefer localizedDescription
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription {
        return description
    }

    // Otherwise use the Error's localizedDescription
    return error.localizedDescription
}

/**
 * Overload for Any? type (equivalent to TypeScript's unknown | undefined).
 */
public func getErrorMessage(_ error: Any?) -> String {
    guard let error = error else {
        return "unknown error"
    }

    if let string = error as? String {
        return string
    }

    if let err = error as? any Error {
        return getErrorMessage(err)
    }

    // For other types, use String interpolation or JSONSerialization
    if let jsonData = try? JSONSerialization.data(withJSONObject: error, options: []),
       let jsonString = String(data: jsonData, encoding: .utf8) {
        return jsonString
    }

    return String(describing: error)
}

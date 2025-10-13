import Foundation

/**
 Extracts a readable error message from any error type.

 Port of `@ai-sdk/provider/src/errors/get-error-message.ts`.

 Handles different error representations:
 - `nil` → "unknown error"
 - `String` → returns as-is
 - `Error` → returns `localizedDescription`
 - Other types → JSON string representation

 - Parameter error: The error to extract message from
 - Returns: A readable error message string

 ## Example
 ```swift
 getErrorMessage(nil)                          // "unknown error"
 getErrorMessage("Connection failed")          // "Connection failed"
 getErrorMessage(URLError(.notConnectedToInternet)) // "The Internet connection appears to be offline."
 getErrorMessage(["code": 500])                // "{\"code\":500}"
 ```
 */
public func getErrorMessage(_ error: Any?) -> String {
    // Handle nil
    if error == nil {
        return "unknown error"
    }

    // Handle String
    if let errorString = error as? String {
        return errorString
    }

    // Handle Error
    if let errorInstance = error as? Error {
        return errorInstance.localizedDescription
    }

    // Handle other types - convert to JSON string
    do {
        let jsonData = try JSONSerialization.data(withJSONObject: error as Any, options: [])
        if let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
    } catch {
        // If JSON serialization fails, use description
    }

    // Fallback: use description
    return String(describing: error!)
}

/**
 Overload for Error? type (convenience for Swift callers).

 Swift adaptation: TypeScript has single function for `unknown | undefined`,
 but Swift benefits from type-specific overload for `Error?`.
 */
public func getErrorMessage(_ error: (any Error)?) -> String {
    guard let error = error else {
        return "unknown error"
    }

    // If it's a LocalizedError, prefer errorDescription
    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription {
        return description
    }

    // Otherwise use Error's localizedDescription
    return error.localizedDescription
}

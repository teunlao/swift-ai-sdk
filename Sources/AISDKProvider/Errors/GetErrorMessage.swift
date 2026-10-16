import Foundation

/**
 Extracts a readable error message from any value.

 Port of `@ai-sdk/provider/src/errors/get-error-message.ts`:
 - `nil` → `"unknown error"`
 - `String` → returned as-is
 - `Error` → its `toString()` equivalent (see `getErrorMessage(_: (any Error)?)`)
 - other values → JSON string representation
 */
public func getErrorMessage(_ error: Any?) -> String {
    guard let error else {
        return "unknown error"
    }

    if let errorString = error as? String {
        return errorString
    }

    if let errorInstance = error as? any Error {
        return getErrorMessage(errorInstance)
    }

    return stringifyErrorValue(error)
}

/**
 Message of an error the way upstream's `Error.prototype.toString()` renders it.

 An AI SDK error renders as `"<name>: <message>"`, or `"<name>"` when the message
 is empty. Other Swift errors carry no type name, so their localized description
 is used.
 */
public func getErrorMessage(_ error: (any Error)?) -> String {
    guard let error = error else {
        return "unknown error"
    }

    if let sdkError = error as? any AISDKError {
        return sdkError.message.isEmpty ? sdkError.name : "\(sdkError.name): \(sdkError.message)"
    }

    if let localizedError = error as? LocalizedError,
       let description = localizedError.errorDescription {
        return description
    }

    return error.localizedDescription
}

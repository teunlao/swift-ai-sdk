import Foundation

/**
 Base64 conversion utilities for Uint8Array ↔ Base64 string.

 Port of `@ai-sdk/provider-utils/src/uint8-utils.ts`.

 These functions mirror the behavior of JavaScript's `btoa` and `atob` functions,
 with support for base64url format (using `-` and `_` instead of `+` and `/`).
 */

/**
 Converts a base64-encoded string to Data.

 Supports both standard base64 and base64url formats (RFC 4648).

 - Parameter base64String: The base64 or base64url encoded string
 - Returns: The decoded Data
 - Throws: `DecodingError` if the base64 string is invalid
 */
public func convertBase64ToData(_ base64String: String) throws -> Data {
    // Convert base64url to standard base64
    let base64Standard = base64String
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")

    // Decode base64
    guard let data = Data(base64Encoded: base64Standard) else {
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Invalid base64 string"
            )
        )
    }

    return data
}

/**
 Converts Data to a base64-encoded string.

 - Parameter data: The data to encode
 - Returns: The base64-encoded string
 */
public func convertDataToBase64(_ data: Data) -> String {
    return data.base64EncodedString()
}

/**
 Converts a string or Data to a base64-encoded string.

 - Parameter value: Either a string (assumed to be already base64) or Data to encode
 - Returns: The base64-encoded string
 */
public func convertToBase64(_ value: StringOrData) -> String {
    switch value {
    case .string(let str):
        return str
    case .data(let data):
        return convertDataToBase64(data)
    }
}

/// Union type for string or Data (used in base64 conversion)
public enum StringOrData: Sendable {
    case string(String)
    case data(Data)
}

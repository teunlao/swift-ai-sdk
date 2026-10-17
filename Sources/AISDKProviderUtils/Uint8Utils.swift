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
    let scalars = base64String.unicodeScalars.filter { ![9, 10, 12, 13, 32].contains($0.value) }
    var base64Standard = String(String.UnicodeScalarView(scalars))
        .replacingOccurrences(of: "-", with: "+")
        .replacingOccurrences(of: "_", with: "/")
    if base64Standard.utf8.count.isMultiple(of: 4) {
        if base64Standard.hasSuffix("==") { base64Standard.removeLast(2) }
        else if base64Standard.hasSuffix("=") { base64Standard.removeLast() }
    }
    let remainder = base64Standard.utf8.count % 4
    let valid = remainder != 1 && base64Standard.utf8.allSatisfy {
        (65...90).contains($0) || (97...122).contains($0) || (48...57).contains($0) || $0 == 43 || $0 == 47
    }
    if remainder == 2 || remainder == 3 {
        base64Standard += String(repeating: "=", count: 4 - remainder)
    }

    // Foundation accepts malformed padding that atob rejects.
    guard valid, let data = Data(base64Encoded: base64Standard) else {
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

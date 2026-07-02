import Foundation

/**
 Normalizes header inputs into a dictionary with lower-case keys.

 Swift port of `@ai-sdk/provider-utils/src/normalize-headers.ts`.
 */
public func normalizeHeaders(
    _ headers: [String: String?]?
) -> [String: String] {
    guard let headers else {
        return [:]
    }

    var normalized: [String: String] = [:]
    for (key, value) in headers {
        if let value {
            normalized[key.lowercased()] = value
        }
    }
    return normalized
}

/**
 Normalizes tuple header entries into a dictionary with lower-case keys.

 This mirrors the upstream `HeadersInit` tuple-array path.
 */
public func normalizeHeaders(
    _ headers: [(String, String?)]
) -> [String: String] {
    var normalized: [String: String] = [:]
    for (key, value) in headers {
        if let value {
            normalized[key.lowercased()] = value
        }
    }
    return normalized
}

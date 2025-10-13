import Foundation

/**
 Appends suffix parts to the `user-agent` header.
 Port of `@ai-sdk/provider-utils/src/with-user-agent-suffix.ts`

 - Parameters:
   - headers: The original headers.
   - userAgentSuffixParts: Parts to append to the user-agent header.
 - Returns: Headers with updated user-agent.
 */
public func withUserAgentSuffix(
    _ headers: [String: String?]?,
    _ userAgentSuffixParts: String...
) -> [String: String] {
    let cleanedHeaders = removeUndefinedEntries(headers ?? [:])

    var normalizedHeaders: [String: String] = [:]
    for (key, value) in cleanedHeaders {
        normalizedHeaders[key.lowercased()] = value
    }

    let currentUserAgent = normalizedHeaders["user-agent"] ?? ""

    let parts = [currentUserAgent] + userAgentSuffixParts
    let newUserAgent = parts.filter { !$0.isEmpty }.joined(separator: " ")

    normalizedHeaders["user-agent"] = newUserAgent

    return normalizedHeaders
}

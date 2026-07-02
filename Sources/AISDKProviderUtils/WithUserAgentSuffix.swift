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
    return withUserAgentSuffix(normalizeHeaders(headers), userAgentSuffixParts)
}

public func withUserAgentSuffix(
    _ headers: [(String, String?)],
    _ userAgentSuffixParts: String...
) -> [String: String] {
    return withUserAgentSuffix(normalizeHeaders(headers), userAgentSuffixParts)
}

private func withUserAgentSuffix(
    _ normalizedHeaders: [String: String],
    _ userAgentSuffixParts: [String]
) -> [String: String] {
    var headers = normalizedHeaders
    let currentUserAgent = headers["user-agent"] ?? ""

    let parts = [currentUserAgent] + userAgentSuffixParts
    let newUserAgent = parts.filter { !$0.isEmpty }.joined(separator: " ")

    headers["user-agent"] = newUserAgent

    return headers
}

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

    let currentUserAgent = cleanedHeaders["user-agent"] ?? ""

    let parts = [currentUserAgent] + userAgentSuffixParts
    let newUserAgent = parts.filter { !$0.isEmpty }.joined(separator: " ")

    var result = cleanedHeaders
    result["user-agent"] = newUserAgent

    return result
}

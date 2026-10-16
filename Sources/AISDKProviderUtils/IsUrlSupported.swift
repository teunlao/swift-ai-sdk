import Foundation

/// Checks if the given URL is supported natively by the model.
///
/// - Parameters:
///   - mediaType: Media type of the URL, case-insensitive: a full `type/subtype`,
///     a wildcard `type/*`, or only the top-level segment (e.g. `image`).
///   - url: The URL to check. Matched case-sensitively: URL paths and query
///     values are case-sensitive.
///   - supportedUrls: Case-insensitive media types (or `*`) mapped to URL patterns.
/// - Returns: `true` if the URL matches a pattern under the specific media type or
///   a wildcard.
///
/// Port of `@ai-sdk/provider-utils/src/is-url-supported.ts`.
public func isUrlSupported(
    mediaType: String,
    url: String,
    supportedUrls: [String: [NSRegularExpression]]
) -> Bool {
    let mediaType = mediaType.lowercased()
    let isTopLevelOnly = !mediaType.contains("/")

    return supportedUrls
        .map { key, regexes -> (mediaTypePrefix: String, regexes: [NSRegularExpression]) in
            let key = key.lowercased()
            if key == "*" || key == "*/*" {
                return ("", regexes)
            }
            // Only the first `*` is removed, as upstream's non-global replace.
            guard let wildcard = key.firstIndex(of: "*") else {
                return (key, regexes)
            }
            var prefix = key
            prefix.remove(at: wildcard)
            return (prefix, regexes)
        }
        .filter { mediaTypePrefix, _ in
            if mediaTypePrefix.isEmpty {
                return true
            }
            // A top-level-only media type cannot tell whether a specific subtype
            // applies, so it matches only the corresponding `type/*` prefix.
            if isTopLevelOnly {
                return "\(mediaType)/" == mediaTypePrefix
            }
            return mediaTypePrefix.hasSuffix("/")
                ? mediaType.hasPrefix(mediaTypePrefix)
                : mediaType == mediaTypePrefix
        }
        .flatMap(\.regexes)
        .contains { regex in
            regex.firstMatch(in: url, range: NSRange(url.startIndex..., in: url)) != nil
        }
}

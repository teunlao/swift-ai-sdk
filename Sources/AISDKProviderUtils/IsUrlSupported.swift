import Foundation

// Port of @ai-sdk/provider-utils/src/is-url-supported.ts
// Checks if the given URL is supported natively by the model based on media type patterns.
public func isUrlSupported(
    mediaType: String,
    url: String,
    supportedUrls: [String: [NSRegularExpression]]
) -> Bool {
    // Standardize to lowercase
    let normalizedUrl = url.lowercased()
    let normalizedMediaType = mediaType.lowercased()

    // Process supported URLs map
    let patterns = supportedUrls
        .map { (key, regexes) -> (mediaTypePrefix: String, regexes: [NSRegularExpression]) in
            let normalizedKey = key.lowercased()
            // Handle wildcard media types
            if normalizedKey == "*" || normalizedKey == "*/*" {
                return ("", regexes)
            } else {
                // Remove trailing wildcard to get prefix (e.g., `"image/*"` → `"image/"`)
                let prefix = normalizedKey.replacingOccurrences(of: "*", with: "")
                return (prefix, regexes)
            }
        }
        // Filter by media type prefix match
        .filter { normalizedMediaType.hasPrefix($0.mediaTypePrefix) }
        // Flatten regexes
        .flatMap { $0.regexes }

    // Check if any pattern matches the URL
    return patterns.contains { regex in
        let range = NSRange(normalizedUrl.startIndex..., in: normalizedUrl)
        return regex.firstMatch(in: normalizedUrl, range: range) != nil
    }
}

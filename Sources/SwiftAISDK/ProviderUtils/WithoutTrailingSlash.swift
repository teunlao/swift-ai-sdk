import Foundation

/**
 Removes trailing slash from a URL string if present.

 Port of `@ai-sdk/provider-utils/src/without-trailing-slash.ts`.

 - Parameter url: The URL string to process (optional)
 - Returns: URL string without trailing slash, or nil if input is nil

 ## Example
 ```swift
 withoutTrailingSlash("https://api.example.com/")  // "https://api.example.com"
 withoutTrailingSlash("https://api.example.com")   // "https://api.example.com"
 withoutTrailingSlash(nil)                          // nil
 ```
 */
public func withoutTrailingSlash(_ url: String?) -> String? {
    guard let url = url else { return nil }
    return url.hasSuffix("/") ? String(url.dropLast()) : url
}

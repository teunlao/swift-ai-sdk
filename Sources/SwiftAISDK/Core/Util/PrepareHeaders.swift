/**
 Prepares HTTP headers by merging provided headers with defaults.

 Port of `@ai-sdk/ai/src/util/prepare-headers.ts`.

 Default headers are only added if the header (case-insensitive) is not already present.
 This matches the behavior of JavaScript's `Headers` API which is case-insensitive.

 - Parameters:
   - headers: Optional initial headers
   - defaultHeaders: Default headers to add if not present

 - Returns: Merged headers dictionary

 - Note: HTTP header names are case-insensitive per RFC 7230. This function performs
         case-insensitive matching but preserves the original case of existing headers.

 Example:
 ```swift
 let headers = prepareHeaders(
     ["Content-Type": "text/html"],
     defaultHeaders: ["content-type": "application/json", "User-Agent": "SDK"]
 )
 // Result: ["Content-Type": "text/html", "User-Agent": "SDK"]
 // Content-Type from original headers is preserved (not overwritten)
 ```
 */
public func prepareHeaders(
    _ headers: [String: String]?,
    defaultHeaders: [String: String]
) -> [String: String] {
    var result = headers ?? [:]

    // Build a case-insensitive lookup map for existing headers
    let existingKeysLowercased = Set(result.keys.map { $0.lowercased() })

    // Add default headers only if not already present (case-insensitive check)
    for (key, value) in defaultHeaders {
        if !existingKeysLowercased.contains(key.lowercased()) {
            result[key] = value
        }
    }

    return result
}

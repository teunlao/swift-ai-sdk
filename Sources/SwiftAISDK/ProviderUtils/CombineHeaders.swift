import Foundation

/**
 Combines multiple header dictionaries into a single dictionary.
 Later headers override earlier ones.

 Port of `@ai-sdk/provider-utils/src/combine-headers.ts`

 - Parameter headers: Variadic array of optional header dictionaries.
 - Returns: A single combined dictionary with all headers. Values from later dictionaries override earlier ones.

 - Note: This function accepts optional dictionaries (`[String: String?]?`) to match TypeScript's
         `Record<string, string | undefined> | undefined` type. Both the dictionary itself and its
         values can be `nil`.
 */
public func combineHeaders(
    _ headers: [String: String?]?...
) -> [String: String?] {
    return headers
        .compactMap { $0 } // Remove nil dictionaries
        .reduce(into: [:]) { result, dict in
            // Explicitly set each key-value pair, preserving nil values
            // This matches TypeScript's spread operator behavior where
            // undefined values are preserved
            for (key, value) in dict {
                result[key] = value
            }
        }
}

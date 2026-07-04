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
    var result: [String: String?] = [:]
    var canonicalKeys: [String: String] = [:]

    for dict in headers.compactMap({ $0 }) {
        for (key, value) in dict {
            let normalizedKey = key.lowercased()

            if let existingKey = canonicalKeys[normalizedKey], existingKey != key {
                result.removeValue(forKey: existingKey)
            }

            canonicalKeys[normalizedKey] = key
            result[key] = value
        }
    }

    return result
}

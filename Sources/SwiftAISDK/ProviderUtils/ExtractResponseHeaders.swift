import Foundation

/**
 Extracts the headers from a response object and returns them as a key-value dictionary.

 Port of `@ai-sdk/provider-utils/src/extract-response-headers.ts`

 - Parameter response: The HTTP response object to extract headers from.
 - Returns: The headers as a `[String: String]` dictionary.

 - Note: This function safely casts `HTTPURLResponse.allHeaderFields` (which has type
         `[AnyHashable: Any]`) to `[String: String]`. Non-string keys or values are filtered out.
 */
public func extractResponseHeaders(from response: HTTPURLResponse) -> [String: String] {
    return Dictionary(
        uniqueKeysWithValues: response.allHeaderFields.compactMap { key, value in
            guard let keyString = key as? String,
                  let valueString = value as? String else {
                return nil
            }
            return (keyString, valueString)
        }
    )
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Converts a value to an array.

 Port of `@ai-sdk/ai/src/util/as-array.ts`.

 This function handles three cases:
 - `nil` → returns empty array `[]`
 - Array → returns the array as-is
 - Single value → wraps in array `[value]`

 - Parameter value: Optional value to convert
 - Returns: Array containing the value
 */
public func asArray<T>(_ value: T?) -> [T] {
    guard let value = value else {
        return []
    }
    return [value]
}

/**
 Overload for array input - returns the array as-is.

 - Parameter value: Optional array
 - Returns: The array, or empty array if nil
 */
public func asArray<T>(_ value: [T]?) -> [T] {
    return value ?? []
}

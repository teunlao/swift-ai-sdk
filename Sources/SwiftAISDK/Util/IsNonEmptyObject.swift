/**
 Checks if a dictionary is non-empty.

 Port of `@ai-sdk/ai/src/util/is-non-empty-object.ts`.

 Returns true if the object is not nil and has at least one key-value pair.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Checks if a dictionary is non-empty.

 - Parameter object: The dictionary to check
 - Returns: true if the dictionary is not nil and has at least one key, false otherwise
 */
public func isNonEmptyObject(_ object: [String: Any]?) -> Bool {
    guard let obj = object else {
        return false
    }
    return obj.count > 0
}

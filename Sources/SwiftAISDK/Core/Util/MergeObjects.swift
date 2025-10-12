/**
 Deeply merges two objects together.

 Port of `@ai-sdk/ai/src/util/merge-objects.ts`.

 - Properties from the `overrides` object override those in the `base` object with the same key.
 - For nested objects, the merge is performed recursively (deep merge).
 - Arrays are replaced, not merged.
 - Primitive values are replaced.
 - If both `base` and `overrides` are nil, returns nil.
 - If one of `base` or `overrides` is nil, returns the other.
 */

import Foundation

/**
 Deeply merges two dictionaries.

 - Parameters:
   - base: The target dictionary to merge into
   - overrides: The source dictionary to merge from
 - Returns: A new dictionary with the merged properties, or nil if both inputs are nil
 */
public func mergeObjects(
    _ base: [String: Any]?,
    _ overrides: [String: Any]?
) -> [String: Any]? {
    // If both inputs are nil, return nil
    if base == nil && overrides == nil {
        return nil
    }

    // If base is nil, return overrides
    if base == nil {
        return overrides
    }

    // If overrides is nil, return base
    if overrides == nil {
        return base
    }

    // Create a new dictionary to avoid mutating the inputs
    var result = base!

    // Iterate through all keys in the overrides object
    for (key, overridesValue) in overrides! {
        // In Swift dictionaries, we can't have nil values (they're omitted).
        // NSNull represents JSON null, which IS a valid value to override with.
        // TypeScript skips only `undefined` (absent values), not `null`.
        // Since Swift dictionaries auto-skip nil, we don't need explicit checks here.

        // Get the base value if it exists
        let baseValue = result[key]

        // Check if both values are objects that can be deeply merged
        let isOverridesObject = isMergeableObject(overridesValue)
        let isBaseObject = baseValue != nil && isMergeableObject(baseValue!)

        // If both values are mergeable objects, merge them recursively
        if isOverridesObject && isBaseObject {
            if let overridesDict = overridesValue as? [String: Any],
               let baseDict = baseValue as? [String: Any] {
                result[key] = mergeObjects(baseDict, overridesDict)
            } else {
                // Fallback: just override
                result[key] = overridesValue
            }
        } else {
            // For primitives, arrays, or when one value is not a mergeable object,
            // simply override with the overrides value
            result[key] = overridesValue
        }
    }

    return result
}

/**
 Checks if a value is a mergeable object (dictionary).

 A value is mergeable if it's:
 - Not nil
 - An object/dictionary
 - Not an array
 - Not a Date
 - Not a NSRegularExpression (Swift equivalent of RegExp)

 - Parameter value: The value to check
 - Returns: true if the value is a mergeable dictionary
 */
private func isMergeableObject(_ value: Any) -> Bool {
    // Check if it's a dictionary
    guard value is [String: Any] else {
        return false
    }

    // Exclude special types that shouldn't be deeply merged
    if value is Date {
        return false
    }

    if value is NSRegularExpression {
        return false
    }

    // It's a plain dictionary
    return true
}

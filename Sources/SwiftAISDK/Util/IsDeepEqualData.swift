/**
 Performs a deep-equal comparison of two parsed JSON objects.

 Port of `@ai-sdk/ai/src/util/is-deep-equal-data.ts`.

 This function recursively compares two objects to determine if they are structurally
 and value-wise equal. It handles primitives, arrays, dictionaries, dates, and other types.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Checks if two values are deeply equal.

 - Parameters:
   - obj1: The first value to compare
   - obj2: The second value to compare
 - Returns: true if the two values are deeply equal, false otherwise
 */
public func isDeepEqualData(_ obj1: Any?, _ obj2: Any?) -> Bool {
    // Check for strict equality first (reference equality or value equality for value types)
    // For optionals, we need to check if both are nil
    if obj1 == nil && obj2 == nil {
        return true
    }

    // Check if either is nil
    if obj1 == nil || obj2 == nil {
        return false
    }

    // Unwrap optionals
    let val1 = obj1!
    let val2 = obj2!

    // Try to compare directly for equatable types
    // This handles primitives (Int, String, Bool, etc.)
    if let v1 = val1 as? any Equatable, let v2 = val2 as? any Equatable {
        // For primitives, we can use type-specific equality
        // But we need to ensure types match first
        if type(of: val1) != type(of: val2) {
            return false
        }
        return isEqual(v1, v2)
    }

    // Check if both are dictionaries
    if let dict1 = val1 as? [String: Any], let dict2 = val2 as? [String: Any] {
        return isDeepEqualDictionaries(dict1, dict2)
    }

    // Check if both are arrays
    if let arr1 = val1 as? [Any], let arr2 = val2 as? [Any] {
        return isDeepEqualArrays(arr1, arr2)
    }

    // Check if both are Dates
    if let date1 = val1 as? Date, let date2 = val2 as? Date {
        return date1.timeIntervalSince1970 == date2.timeIntervalSince1970
    }

    // Check type mismatch (one is object, other is not)
    // This catches cases like comparing dictionary with array
    let type1 = type(of: val1)
    let type2 = type(of: val2)
    if type1 != type2 {
        return false
    }

    // For functions and other types that don't support equality,
    // different instances are never equal (like JavaScript behavior)
    // Functions are compared by reference in both JavaScript and Swift
    return false
}

/**
 Helper to compare two Equatable values dynamically.
 */
private func isEqual(_ lhs: any Equatable, _ rhs: any Equatable) -> Bool {
    // This is a workaround for comparing existential Equatable types
    // We try to cast both to the same concrete type and compare
    let mirror1 = Mirror(reflecting: lhs)
    let mirror2 = Mirror(reflecting: rhs)

    // If they're different types, they can't be equal
    if mirror1.subjectType != mirror2.subjectType {
        return false
    }

    // For primitives, we can safely compare by converting to string representation
    // This is a fallback that works for most value types
    return "\(lhs)" == "\(rhs)"
}

/**
 Deep equality check for dictionaries.
 */
private func isDeepEqualDictionaries(_ dict1: [String: Any], _ dict2: [String: Any]) -> Bool {
    // Compare key counts
    if dict1.count != dict2.count {
        return false
    }

    // Check each key-value pair recursively
    for (key, value1) in dict1 {
        guard let value2 = dict2[key] else {
            return false // Key missing in dict2
        }
        if !isDeepEqualData(value1, value2) {
            return false
        }
    }

    return true
}

/**
 Deep equality check for arrays.
 */
private func isDeepEqualArrays(_ arr1: [Any], _ arr2: [Any]) -> Bool {
    // Compare lengths
    if arr1.count != arr2.count {
        return false
    }

    // Compare each element recursively
    for i in 0..<arr1.count {
        if !isDeepEqualData(arr1[i], arr2[i]) {
            return false
        }
    }

    return true
}

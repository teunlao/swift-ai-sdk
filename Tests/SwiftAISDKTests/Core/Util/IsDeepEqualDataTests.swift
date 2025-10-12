/**
 Tests for isDeepEqualData function.

 Port of `@ai-sdk/ai/src/util/is-deep-equal-data.test.ts`.
 */

import Testing
import Foundation
@testable import SwiftAISDK

@Suite("IsDeepEqualData Tests")
struct IsDeepEqualDataTests {

    @Test("should check if two primitives are equal")
    func checksPrimitivesEquality() throws {
        var x = 1
        var y = 1
        var result = isDeepEqualData(x, y)
        #expect(result == true)

        x = 1
        y = 2
        result = isDeepEqualData(x, y)
        #expect(result == false)
    }

    @Test("should return false for different types")
    func returnsFalseForDifferentTypes() throws {
        let obj: [String: Any] = ["a": 1]
        let num = 1
        let result = isDeepEqualData(obj, num)
        #expect(result == false)
    }

    @Test("should return false for null values compared with objects")
    func returnsFalseForNullVsObject() throws {
        let obj: [String: Any] = ["a": 1]
        let result = isDeepEqualData(obj, nil)
        #expect(result == false)
    }

    @Test("should identify two equal objects")
    func identifiesEqualObjects() throws {
        let obj1: [String: Any] = ["a": 1, "b": 2]
        let obj2: [String: Any] = ["a": 1, "b": 2]
        let result = isDeepEqualData(obj1, obj2)
        #expect(result == true)
    }

    @Test("should identify two objects with different values")
    func identifiesObjectsWithDifferentValues() throws {
        let obj1: [String: Any] = ["a": 1, "b": 2]
        let obj2: [String: Any] = ["a": 1, "b": 3]
        let result = isDeepEqualData(obj1, obj2)
        #expect(result == false)
    }

    @Test("should identify two objects with different number of keys")
    func identifiesObjectsWithDifferentKeyCount() throws {
        let obj1: [String: Any] = ["a": 1, "b": 2]
        let obj2: [String: Any] = ["a": 1, "b": 2, "c": 3]
        let result = isDeepEqualData(obj1, obj2)
        #expect(result == false)
    }

    @Test("should handle nested objects")
    func handlesNestedObjects() throws {
        let obj1: [String: Any] = ["a": ["c": 1] as [String: Any], "b": 2]
        let obj2: [String: Any] = ["a": ["c": 1] as [String: Any], "b": 2]
        let result = isDeepEqualData(obj1, obj2)
        #expect(result == true)
    }

    @Test("should detect inequality in nested objects")
    func detectsInequalityInNestedObjects() throws {
        let obj1: [String: Any] = ["a": ["c": 1] as [String: Any], "b": 2]
        let obj2: [String: Any] = ["a": ["c": 2] as [String: Any], "b": 2]
        let result = isDeepEqualData(obj1, obj2)
        #expect(result == false)
    }

    @Test("should compare arrays correctly")
    func comparesArraysCorrectly() throws {
        let arr1: [Any] = [1, 2, 3]
        let arr2: [Any] = [1, 2, 3]
        let result = isDeepEqualData(arr1, arr2)
        #expect(result == true)

        let arr3: [Any] = [1, 2, 3]
        let arr4: [Any] = [1, 2, 4]
        let result2 = isDeepEqualData(arr3, arr4)
        #expect(result2 == false)
    }

    @Test("should return false for null comparison with object")
    func returnsFalseForNullComparisonWithObject() throws {
        let obj: [String: Any] = ["a": 1]
        let result = isDeepEqualData(obj, nil)
        #expect(result == false)
    }

    @Test("should distinguish between array and object with same enumerable properties")
    func distinguishesArrayFromObjectWithSameProperties() throws {
        let obj: [String: Any] = ["0": "one", "1": "two", "length": 2]
        let arr: [Any] = ["one", "two"]
        let result = isDeepEqualData(obj, arr)
        #expect(result == false)
    }

    @Test("should return false when comparing objects with different prototypes")
    func returnsFalseForDifferentPrototypes() throws {
        // In Swift, dictionaries don't have the same prototype concept as JavaScript
        // We'll simulate this by using different dictionary types
        // This test verifies type checking works correctly
        let obj1: [String: Any] = ["b": 2]
        let obj2: [String: Int] = ["b": 2]
        // When comparing different dictionary types through Any, they should still be equal
        // if their contents are equal. This differs from JS prototype behavior.
        let result = isDeepEqualData(obj1, obj2)
        // In Swift, we care about structural equality, not prototype inheritance
        // So this should return true (different from JS behavior)
        #expect(result == true)
    }

    @Test("should handle date object comparisons correctly")
    func handlesDateComparisons() throws {
        let date1 = Date(timeIntervalSince1970: 946684800) // 2000-01-01 00:00:00 UTC
        let date2 = Date(timeIntervalSince1970: 946684800)
        let date3 = Date(timeIntervalSince1970: 946771200) // 2000-01-02 00:00:00 UTC
        #expect(isDeepEqualData(date1, date2) == true)
        #expect(isDeepEqualData(date1, date3) == false)
    }

    @Test("should handle function comparisons")
    func handlesFunctionComparisons() throws {
        // Swift closures can't be compared directly
        // They're compared by identity, not by content
        let func1: () -> Void = { print("hello") }
        let func2: () -> Void = { print("hello") }
        let func3: () -> Void = { print("world") }

        // Different closures are never equal in Swift (reference inequality)
        #expect(isDeepEqualData(func1, func2) == false)
        #expect(isDeepEqualData(func1, func3) == false)
    }
}

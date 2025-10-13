/**
 Tests for mergeObjects function.

 Port of `@ai-sdk/ai/src/util/merge-objects.test.ts`.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("MergeObjects Tests")
struct MergeObjectsTests {

    @Test("should merge two flat objects")
    func mergesTwoFlatObjects() throws {
        let base: [String: Any] = ["a": 1, "b": 2]
        let overrides: [String: Any] = ["b": 3, "c": 4]
        let result = mergeObjects(base, overrides)

        // Check result
        #expect(result != nil)
        let r = result!
        #expect(r["a"] as? Int == 1)
        #expect(r["b"] as? Int == 3)
        #expect(r["c"] as? Int == 4)

        // Original objects should not be modified
        #expect(base["a"] as? Int == 1)
        #expect(base["b"] as? Int == 2)
        #expect(overrides["b"] as? Int == 3)
        #expect(overrides["c"] as? Int == 4)
    }

    @Test("should deeply merge nested objects")
    func deeplyMergesNestedObjects() throws {
        let base: [String: Any] = [
            "a": 1,
            "b": ["c": 2, "d": 3]
        ]
        let overrides: [String: Any] = [
            "b": ["c": 4, "e": 5]
        ]
        let result = mergeObjects(base, overrides)

        // Check result
        #expect(result != nil)
        let r = result!
        #expect(r["a"] as? Int == 1)

        let b = r["b"] as? [String: Any]
        #expect(b != nil)
        #expect(b!["c"] as? Int == 4)
        #expect(b!["d"] as? Int == 3)
        #expect(b!["e"] as? Int == 5)
    }

    @Test("should replace arrays instead of merging them")
    func replacesArraysInsteadOfMerging() throws {
        let base: [String: Any] = ["a": [1, 2, 3], "b": 2]
        let overrides: [String: Any] = ["a": [4, 5]]
        let result = mergeObjects(base, overrides)

        // Check result
        #expect(result != nil)
        let r = result!
        let a = r["a"] as? [Int]
        #expect(a != nil)
        #expect(a! == [4, 5])
        #expect(r["b"] as? Int == 2)
    }

    @Test("should handle null and undefined values")
    func handlesNullAndUndefinedValues() throws {
        // In Swift, dictionaries can't store nil directly, but can store NSNull
        // TypeScript undefined is represented by omitting the key
        let base: [String: Any] = ["a": 1, "b": NSNull(), "c": "defined"]
        let overrides: [String: Any] = ["a": NSNull(), "b": 2, "d": NSNull()]

        let result = mergeObjects(base, overrides)

        // Check result
        #expect(result != nil)
        let r = result!
        // "a" should be replaced with NSNull (null in JSON)
        #expect(r["a"] is NSNull)
        // "b" should be replaced with 2
        #expect(r["b"] as? Int == 2)
        // "c" should remain
        #expect(r["c"] as? String == "defined")
        // "d" is NSNull in overrides, so it's skipped (undefined behavior)
        // In the original test, undefined values are NOT added to result
    }

    @Test("should handle complex nested structures")
    func handlesComplexNestedStructures() throws {
        let base: [String: Any] = [
            "a": 1,
            "b": [
                "c": [1, 2, 3],
                "d": [
                    "e": 4,
                    "f": 5
                ]
            ]
        ]
        let overrides: [String: Any] = [
            "b": [
                "c": [4, 5],
                "d": [
                    "f": 6,
                    "g": 7
                ]
            ],
            "h": 8
        ]

        let result = mergeObjects(base, overrides)

        // Check result
        #expect(result != nil)
        let r = result!
        #expect(r["a"] as? Int == 1)
        #expect(r["h"] as? Int == 8)

        let b = r["b"] as? [String: Any]
        #expect(b != nil)

        let c = b!["c"] as? [Int]
        #expect(c == [4, 5])

        let d = b!["d"] as? [String: Any]
        #expect(d != nil)
        #expect(d!["e"] as? Int == 4)
        #expect(d!["f"] as? Int == 6)
        #expect(d!["g"] as? Int == 7)
    }

    @Test("should handle Date objects")
    func handlesDateObjects() throws {
        let formatter = ISO8601DateFormatter()
        let date1 = formatter.date(from: "2023-01-01T00:00:00Z")!
        let date2 = formatter.date(from: "2023-02-01T00:00:00Z")!

        let base: [String: Any] = ["a": date1]
        let overrides: [String: Any] = ["a": date2]
        let result = mergeObjects(base, overrides)

        // Date objects should be replaced, not merged
        #expect(result != nil)
        let r = result!
        let resultDate = r["a"] as? Date
        #expect(resultDate == date2)
    }

    @Test("should handle RegExp objects")
    func handlesRegExpObjects() throws {
        let regex1 = try NSRegularExpression(pattern: "abc", options: [])
        let regex2 = try NSRegularExpression(pattern: "def", options: [])

        let base: [String: Any] = ["a": regex1]
        let overrides: [String: Any] = ["a": regex2]
        let result = mergeObjects(base, overrides)

        // RegExp objects should be replaced, not merged
        #expect(result != nil)
        let r = result!
        let resultRegex = r["a"] as? NSRegularExpression
        #expect(resultRegex?.pattern == regex2.pattern)
    }

    @Test("should handle empty objects")
    func handlesEmptyObjects() throws {
        // Empty base
        let base1: [String: Any] = [:]
        let overrides1: [String: Any] = ["a": 1]
        let result1 = mergeObjects(base1, overrides1)
        #expect(result1 != nil)
        #expect(result1!["a"] as? Int == 1)

        // Empty overrides
        let base2: [String: Any] = ["a": 1]
        let overrides2: [String: Any] = [:]
        let result2 = mergeObjects(base2, overrides2)
        #expect(result2 != nil)
        #expect(result2!["a"] as? Int == 1)
    }

    @Test("should handle undefined inputs")
    func handlesUndefinedInputs() throws {
        // Both inputs nil
        let result1 = mergeObjects(nil, nil)
        #expect(result1 == nil)

        // One input nil
        let base: [String: Any] = ["a": 1]
        let result2 = mergeObjects(base, nil)
        #expect(result2 != nil)
        #expect(result2!["a"] as? Int == 1)

        let overrides: [String: Any] = ["b": 2]
        let result3 = mergeObjects(nil, overrides)
        #expect(result3 != nil)
        #expect(result3!["b"] as? Int == 2)
    }
}

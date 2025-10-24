/**
 Tests for fixJson function.

 Port of `@ai-sdk/ai/src/util/fix-json.test.ts`.

 Tests cover all scenarios: empty input, literals, numbers, strings, arrays, objects,
 nesting, and regression cases.
 */

import Foundation
import Testing

@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("fixJson")
struct FixJsonTests {
    @Test("should handle empty input")
    func testEmptyInput() throws {
        #expect(fixJson("") == "")
    }

    // MARK: - Literals

    @Test("should handle incomplete null")
    func testIncompleteNull() throws {
        #expect(fixJson("nul") == "null")
    }

    @Test("should handle incomplete true")
    func testIncompleteTrue() throws {
        #expect(fixJson("t") == "true")
    }

    @Test("should handle incomplete false")
    func testIncompleteFalse() throws {
        #expect(fixJson("fals") == "false")
    }

    // MARK: - Numbers

    @Test("should handle incomplete numbers")
    func testIncompleteNumbers() throws {
        #expect(fixJson("12.") == "12")
    }

    @Test("should handle numbers with dot")
    func testNumbersWithDot() throws {
        #expect(fixJson("12.2") == "12.2")
    }

    @Test("should handle negative numbers")
    func testNegativeNumbers() throws {
        #expect(fixJson("-12") == "-12")
    }

    @Test("should handle incomplete negative numbers")
    func testIncompleteNegativeNumbers() throws {
        #expect(fixJson("-") == "")
    }

    @Test("should handle e-notation numbers")
    func testENotationNumbers() throws {
        #expect(fixJson("2.5e") == "2.5")
        #expect(fixJson("2.5e-") == "2.5")
        #expect(fixJson("2.5e3") == "2.5e3")
        #expect(fixJson("-2.5e3") == "-2.5e3")
    }

    @Test("should handle uppercase e-notation numbers")
    func testUppercaseENotationNumbers() throws {
        #expect(fixJson("2.5E") == "2.5")
        #expect(fixJson("2.5E-") == "2.5")
        #expect(fixJson("2.5E3") == "2.5E3")
        #expect(fixJson("-2.5E3") == "-2.5E3")
    }

    @Test("should handle incomplete numbers with e notation")
    func testIncompleteNumbersWithENotation() throws {
        #expect(fixJson("12.e") == "12")
        #expect(fixJson("12.34e") == "12.34")
        #expect(fixJson("5e") == "5")
    }

    // MARK: - Strings

    @Test("should handle incomplete strings")
    func testIncompleteStrings() throws {
        #expect(fixJson("\"abc") == "\"abc\"")
    }

    @Test("should handle escape sequences")
    func testEscapeSequences() throws {
        #expect(
            fixJson("\"value with \\\"quoted\\\" text and \\\\ escape")
                == "\"value with \\\"quoted\\\" text and \\\\ escape\""
        )
    }

    @Test("should handle incomplete escape sequences")
    func testIncompleteEscapeSequences() throws {
        #expect(fixJson("\"value with \\") == "\"value with \"")
    }

    @Test("should handle unicode characters")
    func testUnicodeCharacters() throws {
        #expect(fixJson("\"value with unicode <\"") == "\"value with unicode <\"")
    }

    // MARK: - Arrays

    @Test("should handle incomplete array")
    func testIncompleteArray() throws {
        #expect(fixJson("[") == "[]")
    }

    @Test("should handle closing bracket after number in array")
    func testClosingBracketAfterNumberInArray() throws {
        #expect(fixJson("[[1], [2") == "[[1], [2]]")
    }

    @Test("should handle closing bracket after string in array")
    func testClosingBracketAfterStringInArray() throws {
        #expect(fixJson("[[\"1\"], [\"2") == "[[\"1\"], [\"2\"]]")
    }

    @Test("should handle closing bracket after literal in array")
    func testClosingBracketAfterLiteralInArray() throws {
        #expect(fixJson("[[false], [nu") == "[[false], [null]]")
    }

    @Test("should handle closing bracket after array in array")
    func testClosingBracketAfterArrayInArray() throws {
        #expect(fixJson("[[[]], [[]") == "[[[]], [[]]]")
    }

    @Test("should handle closing bracket after object in array")
    func testClosingBracketAfterObjectInArray() throws {
        #expect(fixJson("[[{}], [{") == "[[{}], [{}]]")
    }

    @Test("should handle trailing comma in array")
    func testTrailingCommaInArray() throws {
        #expect(fixJson("[1, ") == "[1]")
    }

    @Test("should handle closing array")
    func testClosingArray() throws {
        #expect(fixJson("[[], 123") == "[[], 123]")
    }

    // MARK: - Objects

    @Test("should handle keys without values")
    func testKeysWithoutValues() throws {
        #expect(fixJson("{\"key\":") == "{}")
    }

    @Test("should handle closing brace after number in object")
    func testClosingBraceAfterNumberInObject() throws {
        #expect(fixJson("{\"a\": {\"b\": 1}, \"c\": {\"d\": 2") == "{\"a\": {\"b\": 1}, \"c\": {\"d\": 2}}")
    }

    @Test("should handle closing brace after string in object")
    func testClosingBraceAfterStringInObject() throws {
        #expect(fixJson("{\"a\": {\"b\": \"1\"}, \"c\": {\"d\": 2") == "{\"a\": {\"b\": \"1\"}, \"c\": {\"d\": 2}}")
    }

    @Test("should handle closing brace after literal in object")
    func testClosingBraceAfterLiteralInObject() throws {
        #expect(fixJson("{\"a\": {\"b\": false}, \"c\": {\"d\": 2") == "{\"a\": {\"b\": false}, \"c\": {\"d\": 2}}")
    }

    @Test("should handle closing brace after array in object")
    func testClosingBraceAfterArrayInObject() throws {
        #expect(fixJson("{\"a\": {\"b\": []}, \"c\": {\"d\": 2") == "{\"a\": {\"b\": []}, \"c\": {\"d\": 2}}")
    }

    @Test("should handle closing brace after object in object")
    func testClosingBraceAfterObjectInObject() throws {
        #expect(fixJson("{\"a\": {\"b\": {}}, \"c\": {\"d\": 2") == "{\"a\": {\"b\": {}}, \"c\": {\"d\": 2}}")
    }

    @Test("should handle partial keys (first key)")
    func testPartialKeysFirstKey() throws {
        #expect(fixJson("{\"ke") == "{}")
    }

    @Test("should handle partial keys (second key)")
    func testPartialKeysSecondKey() throws {
        #expect(fixJson("{\"k1\": 1, \"k2") == "{\"k1\": 1}")
    }

    @Test("should handle partial keys with colon (second key)")
    func testPartialKeysWithColonSecondKey() throws {
        #expect(fixJson("{\"k1\": 1, \"k2\":") == "{\"k1\": 1}")
    }

    @Test("should handle trailing whitespace")
    func testTrailingWhitespace() throws {
        #expect(fixJson("{\"key\": \"value\"  ") == "{\"key\": \"value\"}")
    }

    @Test("should handle closing after empty object")
    func testClosingAfterEmptyObject() throws {
        #expect(fixJson("{\"a\": {\"b\": {}") == "{\"a\": {\"b\": {}}}")
    }

    // MARK: - Nesting

    @Test("should handle nested arrays with numbers")
    func testNestedArraysWithNumbers() throws {
        #expect(fixJson("[1, [2, 3, [") == "[1, [2, 3, []]]")
    }

    @Test("should handle nested arrays with literals")
    func testNestedArraysWithLiterals() throws {
        #expect(fixJson("[false, [true, [") == "[false, [true, []]]")
    }

    @Test("should handle nested objects")
    func testNestedObjects() throws {
        #expect(fixJson("{\"key\": {\"subKey\":") == "{\"key\": {}}")
    }

    @Test("should handle nested objects with numbers")
    func testNestedObjectsWithNumbers() throws {
        #expect(fixJson("{\"key\": 123, \"key2\": {\"subKey\":") == "{\"key\": 123, \"key2\": {}}")
    }

    @Test("should handle nested objects with literals")
    func testNestedObjectsWithLiterals() throws {
        #expect(fixJson("{\"key\": null, \"key2\": {\"subKey\":") == "{\"key\": null, \"key2\": {}}")
    }

    @Test("should handle arrays within objects")
    func testArraysWithinObjects() throws {
        #expect(fixJson("{\"key\": [1, 2, {") == "{\"key\": [1, 2, {}]}")
    }

    @Test("should handle objects within arrays")
    func testObjectsWithinArrays() throws {
        #expect(fixJson("[1, 2, {\"key\": \"value\",") == "[1, 2, {\"key\": \"value\"}]")
    }

    @Test("should handle nested arrays and objects")
    func testNestedArraysAndObjects() throws {
        #expect(fixJson("{\"a\": {\"b\": [\"c\", {\"d\": \"e\",") == "{\"a\": {\"b\": [\"c\", {\"d\": \"e\"}]}}")
    }

    @Test("should handle deeply nested objects")
    func testDeeplyNestedObjects() throws {
        #expect(fixJson("{\"a\": {\"b\": {\"c\": {\"d\":") == "{\"a\": {\"b\": {\"c\": {}}}}")
    }

    @Test("should handle potential nested arrays or objects")
    func testPotentialNestedArraysOrObjects() throws {
        #expect(fixJson("{\"a\": 1, \"b\": [") == "{\"a\": 1, \"b\": []}")
        #expect(fixJson("{\"a\": 1, \"b\": {") == "{\"a\": 1, \"b\": {}}")
        #expect(fixJson("{\"a\": 1, \"b\": \"") == "{\"a\": 1, \"b\": \"\"}")
    }

    // MARK: - Regression

    @Test("should handle complex nesting 1")
    func testComplexNesting1() throws {
        let input = """
            {
              "a": [
                {
                  "a1": "v1",
                  "a2": "v2",
                  "a3": "v3"
                }
              ],
              "b": [
                {
                  "b1": "n
            """

        let expected = """
            {
              "a": [
                {
                  "a1": "v1",
                  "a2": "v2",
                  "a3": "v3"
                }
              ],
              "b": [
                {
                  "b1": "n"}]}
            """

        #expect(fixJson(input) == expected)
    }

    @Test("should handle empty objects inside nested objects and arrays")
    func testEmptyObjectsInsideNestedObjectsAndArrays() throws {
        #expect(
            fixJson("{\"type\":\"div\",\"children\":[{\"type\":\"Card\",\"props\":{}") == "{\"type\":\"div\",\"children\":[{\"type\":\"Card\",\"props\":{}}]}"
        )
    }
}

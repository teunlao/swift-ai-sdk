/**
 Tests for parsePartialJson function.

 Port of `@ai-sdk/ai/src/util/parse-partial-json.test.ts`.

 Tests cover all parsing scenarios: undefined input, valid JSON, partial JSON repair,
 and invalid JSON that cannot be repaired.

 Note: Unlike upstream tests that use mocking, these tests use real implementations
 to verify actual behavior.
 */

import Foundation
import Testing

@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("parsePartialJson")
struct ParsePartialJsonTests {
    @Test("should handle nullish input")
    func testNullishInput() async throws {
        let result = await parsePartialJson(nil)
        #expect(result.value == nil)
        #expect(result.state == .undefinedInput)
    }

    @Test("should parse valid JSON")
    func testValidJSON() async throws {
        let validJson = "{\"key\": \"value\"}"
        let result = await parsePartialJson(validJson)

        #expect(result.state == .successfulParse)
        #expect(result.value != nil)

        if case .object(let dict) = result.value {
            #expect(dict["key"] == .string("value"))
        } else {
            Issue.record("Expected object value")
        }
    }

    @Test("should repair and parse partial JSON")
    func testPartialJSON() async throws {
        let partialJson = "{\"key\": \"value\""
        let result = await parsePartialJson(partialJson)

        #expect(result.state == .repairedParse)
        #expect(result.value != nil)

        if case .object(let dict) = result.value {
            #expect(dict["key"] == .string("value"))
        } else {
            Issue.record("Expected object value")
        }
    }

    @Test("should handle invalid JSON that cannot be repaired")
    func testInvalidJSON() async throws {
        let invalidJson = "not json at all"
        let result = await parsePartialJson(invalidJson)

        #expect(result.value == nil)
        #expect(result.state == .failedParse)
    }

    // MARK: - Additional Tests

    @Test("should handle empty string")
    func testEmptyString() async throws {
        let result = await parsePartialJson("")

        // Empty string is invalid JSON
        #expect(result.state == .failedParse)
        #expect(result.value == nil)
    }

    @Test("should handle incomplete array")
    func testIncompleteArray() async throws {
        let partialJson = "[1, 2, 3"
        let result = await parsePartialJson(partialJson)

        #expect(result.state == .repairedParse)
        #expect(result.value != nil)

        guard case .array(let arr) = result.value else {
            Issue.record("Expected array value, got: \(String(describing: result.value))")
            return
        }

        #expect(arr.count == 3)
        #expect(arr[0] == .number(1))
        #expect(arr[1] == .number(2))
        #expect(arr[2] == .number(3))
    }

    @Test("should handle incomplete nested object")
    func testIncompleteNestedObject() async throws {
        let partialJson = "{\"a\": {\"b\": 1}, \"c\": {\"d\": 2"
        let result = await parsePartialJson(partialJson)

        #expect(result.state == .repairedParse)
        #expect(result.value != nil)

        if case .object(let dict) = result.value {
            #expect(dict["a"] != nil)
            #expect(dict["c"] != nil)
        } else {
            Issue.record("Expected object value")
        }
    }

    @Test("should handle incomplete literal")
    func testIncompleteLiteral() async throws {
        let partialJson = "{\"flag\": tru"
        let result = await parsePartialJson(partialJson)

        #expect(result.state == .repairedParse)
        #expect(result.value != nil)

        if case .object(let dict) = result.value,
           case .bool(let flag) = dict["flag"]
        {
            #expect(flag == true)
        } else {
            Issue.record("Expected object with boolean flag")
        }
    }

    @Test("should repair partial object prefix")
    func testPartialObjectPrefix() async throws {
        let result = await parsePartialJson("{ ")

        #expect(result.state == .repairedParse)

        if case .object(let dict) = result.value {
            #expect(dict.isEmpty)
        } else {
            Issue.record("Expected empty object")
        }
    }

    @Test("should handle valid complex JSON")
    func testValidComplexJSON() async throws {
        let validJson = """
            {
              "name": "test",
              "values": [1, 2, 3],
              "nested": {
                "flag": true,
                "count": null
              }
            }
            """
        let result = await parsePartialJson(validJson)

        #expect(result.state == .successfulParse)
        #expect(result.value != nil)

        if case .object(let dict) = result.value {
            #expect(dict["name"] == .string("test"))
            #expect(dict["values"] != nil)
            #expect(dict["nested"] != nil)
        } else {
            Issue.record("Expected object value")
        }
    }
}

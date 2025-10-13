import Testing
import Foundation
@testable import SwiftAISDK

/**
 Tests for createToolModelOutput function.

 Port of `@ai-sdk/ai/src/prompt/create-tool-model-output.test.ts`.

 Tests cover:
 - Error cases (text/json error modes)
 - Tool with custom toModelOutput
 - String output without toModelOutput
 - Non-string output without toModelOutput
 - Edge cases
 */

@Suite("createToolModelOutput")
struct CreateToolModelOutputTests {

    // MARK: - Error Cases

    @Suite("error cases")
    struct ErrorCasesTests {

        @Test("should return error type with string value when errorMode is text and output is string")
        func errorTextWithString() {
            let result = createToolModelOutput(
                output: "Error message",
                tool: nil,
                errorMode: .text
            )

            #expect(result == .errorText(value: "Error message"))
        }

        @Test("should return error type with JSON stringified value when errorMode is text and output is not string")
        func errorTextWithObject() {
            let errorOutput: [String: Any] = ["error": "Something went wrong", "code": 500]
            let result = createToolModelOutput(
                output: errorOutput,
                tool: nil,
                errorMode: .text
            )

            // Check it's error-text and contains both keys (order may vary in Swift)
            guard case .errorText(let value) = result else {
                Issue.record("Expected errorText result")
                return
            }
            #expect(value.contains("\"error\":\"Something went wrong\""))
            #expect(value.contains("\"code\":500"))
        }

        @Test("should return error type with JSON stringified value for complex objects")
        func errorTextWithComplexObject() {
            let complexError: [String: Any] = [
                "message": "Complex error",
                "details": [
                    "timestamp": "2023-01-01T00:00:00Z",
                    "stack": ["line1", "line2"]
                ] as [String: Any]
            ]
            let result = createToolModelOutput(
                output: complexError,
                tool: nil,
                errorMode: .text
            )

            // We expect JSON serialization (order may vary, so check it's error-text type)
            guard case .errorText(let value) = result else {
                Issue.record("Expected errorText result")
                return
            }
            #expect(value.contains("Complex error"))
            #expect(value.contains("timestamp"))
            #expect(value.contains("line1"))
        }
    }

    // MARK: - Tool with toModelOutput

    @Suite("tool with toModelOutput")
    struct ToolWithToModelOutputTests {

        @Test("should use tool.toModelOutput when available")
        func usesToModelOutput() {
            let mockTool = Tool(
                description: "Mock tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object")
                ]))),
                toModelOutput: { output in
                    // Extract string value from JSONValue for interpolation
                    let outputStr: String
                    if case .string(let str) = output {
                        outputStr = str
                    } else {
                        outputStr = String(describing: output)
                    }

                    // Return LanguageModelV3ToolResultOutput directly
                    return .text(value: "Custom output: \(outputStr)")
                }
            )

            let result = createToolModelOutput(
                output: "test output",
                tool: mockTool,
                errorMode: .none
            )

            #expect(result == .text(value: "Custom output: test output"))
        }

        @Test("should use tool.toModelOutput with complex output")
        func usesToModelOutputWithComplexData() {
            let mockTool = Tool(
                description: "Mock tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object")
                ]))),
                toModelOutput: { output in
                    return .json(value: .object([
                        "processed": output,
                        "timestamp": .string("2023-01-01")
                    ]))
                }
            )

            let complexOutput: [String: Any] = ["data": [1, 2, 3], "status": "success"]
            let result = createToolModelOutput(
                output: complexOutput,
                tool: mockTool,
                errorMode: .none
            )

            guard case .json(let value) = result,
                  case .object(let obj) = value else {
                Issue.record("Expected json result with object value")
                return
            }

            #expect(obj["timestamp"] == .string("2023-01-01"))
            #expect(obj["processed"] != nil)
        }

        @Test("should use tool.toModelOutput returning content type")
        func usesToModelOutputReturningContent() {
            let mockTool = Tool(
                description: "Mock tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object")
                ]))),
                toModelOutput: { _ in
                    return .content(value: [
                        .text(text: "Here is the result:"),
                        .text(text: "Additional information")
                    ])
                }
            )

            let result = createToolModelOutput(
                output: "any output",
                tool: mockTool,
                errorMode: .none
            )

            guard case .content(let contentParts) = result else {
                Issue.record("Expected content result")
                return
            }

            #expect(contentParts.count == 2)
            #expect(contentParts[0] == .text(text: "Here is the result:"))
            #expect(contentParts[1] == .text(text: "Additional information"))
        }
    }

    // MARK: - String Output Without toModelOutput

    @Suite("string output without toModelOutput")
    struct StringOutputTests {

        @Test("should return text type for string output")
        func textTypeForString() {
            let result = createToolModelOutput(
                output: "Simple string output",
                tool: nil,
                errorMode: .none
            )

            #expect(result == .text(value: "Simple string output"))
        }

        @Test("should return text type for string output even with tool that has no toModelOutput")
        func textTypeForStringWithToolWithoutToModelOutput() {
            let toolWithoutToModelOutput = Tool(
                description: "A tool without toModelOutput",
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object")
                ])))
            )

            let result = createToolModelOutput(
                output: "String output",
                tool: toolWithoutToModelOutput,
                errorMode: .none
            )

            #expect(result == .text(value: "String output"))
        }

        @Test("should return text type for empty string")
        func textTypeForEmptyString() {
            let result = createToolModelOutput(
                output: "",
                tool: nil,
                errorMode: .none
            )

            #expect(result == .text(value: ""))
        }
    }

    // MARK: - Non-String Output Without toModelOutput

    @Suite("non-string output without toModelOutput")
    struct NonStringOutputTests {

        @Test("should return json type for object output")
        func jsonTypeForObject() {
            let objectOutput: [String: Any] = ["result": "success", "data": [1, 2, 3]]
            let result = createToolModelOutput(
                output: objectOutput,
                tool: nil,
                errorMode: .none
            )

            guard case .json(let value) = result,
                  case .object(let obj) = value else {
                Issue.record("Expected json result with object value")
                return
            }

            #expect(obj["result"] == .string("success"))
            if case .array(let dataArray) = obj["data"] {
                #expect(dataArray == [.number(1), .number(2), .number(3)])
            } else {
                Issue.record("Expected data to be array")
            }
        }

        @Test("should return json type for array output")
        func jsonTypeForArray() {
            let arrayOutput: [Any] = [1, 2, 3, "test"]
            let result = createToolModelOutput(
                output: arrayOutput,
                tool: nil,
                errorMode: .none
            )

            let expected: JSONValue = .array([.number(1), .number(2), .number(3), .string("test")])
            #expect(result == .json(value: expected))
        }

        @Test("should return json type for number output")
        func jsonTypeForNumber() {
            let result = createToolModelOutput(
                output: 42,
                tool: nil,
                errorMode: .none
            )

            #expect(result == .json(value: .number(42)))
        }

        @Test("should return json type for boolean output")
        func jsonTypeForBoolean() {
            let result = createToolModelOutput(
                output: true,
                tool: nil,
                errorMode: .none
            )

            #expect(result == .json(value: .bool(true)))
        }

        @Test("should return json type for null output")
        func jsonTypeForNull() {
            let result = createToolModelOutput(
                output: nil,
                tool: nil,
                errorMode: .none
            )

            #expect(result == .json(value: .null))
        }

        @Test("should return json type for complex nested object")
        func jsonTypeForComplexNestedObject() {
            let complexOutput: [String: Any] = [
                "user": [
                    "id": 123,
                    "name": "John Doe",
                    "preferences": [
                        "theme": "dark",
                        "notifications": true
                    ] as [String: Any]
                ] as [String: Any],
                "metadata": [
                    "timestamp": "2023-01-01T00:00:00Z",
                    "version": "1.0.0"
                ] as [String: Any],
                "items": [
                    ["id": 1, "name": "Item 1"],
                    ["id": 2, "name": "Item 2"]
                ] as [[String: Any]]
            ]

            let result = createToolModelOutput(
                output: complexOutput,
                tool: nil,
                errorMode: .none
            )

            guard case .json(let value) = result,
                  case .object(let obj) = value else {
                Issue.record("Expected json result with object value")
                return
            }

            #expect(obj["user"] != nil)
            #expect(obj["metadata"] != nil)
            #expect(obj["items"] != nil)
        }
    }

    // MARK: - Edge Cases

    @Suite("edge cases")
    struct EdgeCasesTests {

        @Test("should prioritize errorMode over tool.toModelOutput")
        func prioritizesErrorMode() {
            let mockTool = Tool(
                description: "Mock tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([
                    "type": .string("object")
                ]))),
                toModelOutput: { _ in
                    return .text(value: "This should not be called")
                }
            )

            let result = createToolModelOutput(
                output: "Error occurred",
                tool: mockTool,
                errorMode: .text
            )

            #expect(result == .errorText(value: "Error occurred"))
        }

        @Test("should handle undefined output in error text case")
        func handlesUndefinedInErrorText() {
            let result = createToolModelOutput(
                output: nil,
                tool: nil,
                errorMode: .text
            )

            #expect(result == .errorText(value: "unknown error"))
        }

        @Test("should use null for undefined output in error json case")
        func usesNullForUndefinedInErrorJson() {
            let result = createToolModelOutput(
                output: nil,
                tool: nil,
                errorMode: .json
            )

            #expect(result == .errorJson(value: .null))
        }

        @Test("should use null for undefined output in non-error case")
        func usesNullForUndefinedInNonError() {
            let result = createToolModelOutput(
                output: nil,
                tool: nil,
                errorMode: .none
            )

            #expect(result == .json(value: .null))
        }
    }
}

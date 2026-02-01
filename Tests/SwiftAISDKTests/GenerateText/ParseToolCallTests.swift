import AISDKProvider
import AISDKProviderUtils
import Foundation
/**
 Tests for parseToolCall helper.

 Port of `@ai-sdk/ai/src/generate-text/parse-tool-call.test.ts`.
 */
import Testing

@testable import SwiftAISDK

/**
 Tests for parseToolCall function.

 Port of `@ai-sdk/ai/src/generate-text/parse-tool-call.test.ts`.
 */

struct ParseToolCallTests {

    // MARK: - Basic Parsing Tests

    @Test("should successfully parse a valid tool call")
    func testSuccessfullyParseValidToolCall() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: #"{"param1": "test", "param2": 42}"#
            ),
            tools: [
                "testTool": tool(
                    title: "Test Tool",
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify static tool call
        guard case .static(let staticCall) = result else {
            Issue.record("Expected static tool call, got \(result)")
            return
        }

        #expect(staticCall.toolCallId == "123")
        #expect(staticCall.toolName == "testTool")
        #expect(staticCall.title == "Test Tool")
        #expect(
            staticCall.input
                == JSONValue.object([
                    "param1": .string("test"),
                    "param2": .number(42),
                ]))
        #expect(staticCall.providerExecuted == nil)
        #expect(staticCall.providerMetadata == nil)
    }

    @Test("should successfully parse a valid tool call with provider metadata")
    func testSuccessfullyParseValidToolCallWithProviderMetadata() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: #"{"param1": "test", "param2": 42}"#,
                providerMetadata: [
                    "testProvider": [
                        "signature": JSONValue.string("sig")
                    ]
                ]
            ),
            tools: [
                "testTool": tool(
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify static tool call with metadata
        guard case .static(let staticCall) = result else {
            Issue.record("Expected static tool call, got \(result)")
            return
        }

        #expect(staticCall.toolCallId == "123")
        #expect(staticCall.toolName == "testTool")
        #expect(
            staticCall.providerMetadata?["testProvider"]?["signature"] == JSONValue.string("sig"))
    }

    @Test("should successfully process empty tool calls for tools that have no inputSchema")
    func testSuccessfullyProcessEmptyToolCallsWithNoInputSchema() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: ""
            ),
            tools: [
                "testTool": tool(
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([:]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify empty object input
        guard case .static(let staticCall) = result else {
            Issue.record("Expected static tool call, got \(result)")
            return
        }

        #expect(staticCall.input == .object([:]))
    }

    @Test("should successfully process empty object tool calls for tools that have no inputSchema")
    func testSuccessfullyProcessEmptyObjectToolCalls() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: "{}"
            ),
            tools: [
                "testTool": tool(
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([:]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify empty object input
        guard case .static(let staticCall) = result else {
            Issue.record("Expected static tool call, got \(result)")
            return
        }

        #expect(staticCall.input == .object([:]))
    }

    // MARK: - Error Handling Tests

    @Test("should return invalid dynamic call when tools is nil")
    func testReturnsInvalidDynamicCallWhenToolsIsNil() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: "{}"
            ),
            tools: nil,
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify invalid dynamic tool call
        guard case .dynamic(let dynamicCall) = result else {
            Issue.record("Expected dynamic tool call, got \(result)")
            return
        }

        #expect(dynamicCall.invalid == true)
        #expect(dynamicCall.toolCallId == "123")
        #expect(dynamicCall.toolName == "testTool")
        #expect(dynamicCall.input == .object([:]))
        #expect(NoSuchToolError.isInstance(dynamicCall.error!))
    }

    @Test("should return invalid dynamic call when tool is not found")
    func testReturnsInvalidDynamicCallWhenToolNotFound() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "nonExistentTool",
                input: "{}"
            ),
            tools: [
                "testTool": tool(
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify invalid dynamic tool call with NoSuchToolError
        guard case .dynamic(let dynamicCall) = result else {
            Issue.record("Expected dynamic tool call, got \(result)")
            return
        }

        #expect(dynamicCall.invalid == true)
        #expect(dynamicCall.toolName == "nonExistentTool")
        #expect(NoSuchToolError.isInstance(dynamicCall.error!))

        // Verify error message includes available tools
        if let error = dynamicCall.error as? NoSuchToolError {
            #expect(error.availableTools == ["testTool"])
        }
    }

    @Test("should return invalid dynamic call when args are invalid")
    func testReturnsInvalidDynamicCallWhenArgsAreInvalid() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: #"{"param1": "test"}"#  // Missing required param2
            ),
            tools: [
                "testTool": tool(
                    title: "Test Tool",
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify invalid dynamic tool call with InvalidToolInputError
        guard case .dynamic(let dynamicCall) = result else {
            Issue.record("Expected dynamic tool call, got \(result)")
            return
        }

        #expect(dynamicCall.invalid == true)
        #expect(dynamicCall.toolName == "testTool")
        #expect(dynamicCall.title == "Test Tool")
        #expect(InvalidToolInputError.isInstance(dynamicCall.error!))

        // Verify parsed input (partial object)
        #expect(
            dynamicCall.input
                == .object([
                    "param1": .string("test")
                ]))
    }

    // MARK: - Tool Call Repair Tests

    @Test("should invoke repairTool when provided and use its result")
    func testInvokesRepairToolAndUsesResult() async throws {
        actor OptionsCapture {
            var callCount = 0
            var options: ToolCallRepairOptions?

            func increment() {
                callCount += 1
            }

            func capture(_ opts: ToolCallRepairOptions) {
                options = opts
            }

            func getCount() -> Int { callCount }
            func getOptions() -> ToolCallRepairOptions? { options }
        }

        let capture = OptionsCapture()

        let repairFunction: ToolCallRepairFunction = { options in
            await capture.increment()
            await capture.capture(options)

            return LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: #"{"param1": "test", "param2": 42}"#
            )
        }

        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: "invalid json"  // This will trigger repair
            ),
            tools: [
                "testTool": tool(
                    title: "Test Tool",
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: repairFunction,
            system: "test system",
            messages: [.user(UserModelMessage(content: .text("test message")))]
        )

        // Verify repair function was called
        let callCount = await capture.getCount()
        let capturedOptions = await capture.getOptions()

        #expect(callCount == 1)
        #expect(capturedOptions != nil)

        if let options = capturedOptions {
            #expect(options.system == "test system")
            #expect(options.messages.count == 1)
            #expect(options.toolCall.input == "invalid json")
            #expect(InvalidToolInputError.isInstance(options.error))
        }

        // Verify the repaired result was used
        guard case .static(let staticCall) = result else {
            Issue.record("Expected static tool call, got \(result)")
            return
        }

        #expect(staticCall.title == "Test Tool")
        #expect(
            staticCall.input
                == JSONValue.object([
                    "param1": .string("test"),
                    "param2": .number(42),
                ]))
    }

    @Test("should return invalid dynamic call if tool call repair returns nil")
    func testReturnsInvalidDynamicCallIfRepairReturnsNil() async throws {
        let repairFunction: ToolCallRepairFunction = { _ in
            return nil  // Repair not possible
        }

        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: "invalid json"
            ),
            tools: [
                "testTool": tool(
                    title: "Test Tool",
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: repairFunction,
            system: nil,
            messages: []
        )

        // Verify invalid dynamic call with original error
        guard case .dynamic(let dynamicCall) = result else {
            Issue.record("Expected dynamic tool call, got \(result)")
            return
        }

        #expect(dynamicCall.invalid == true)
        #expect(InvalidToolInputError.isInstance(dynamicCall.error!))
        #expect(dynamicCall.title == "Test Tool")
        #expect(dynamicCall.input == .string("invalid json"))
    }

    @Test("should return invalid dynamic call with ToolCallRepairError if repairToolCall throws")
    func testReturnsInvalidDynamicCallIfRepairThrows() async throws {
        struct TestError: Error {}

        let repairFunction: ToolCallRepairFunction = { _ in
            throw TestError()
        }

        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: "invalid json"
            ),
            tools: [
                "testTool": tool(
                    title: "Test Tool",
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ])))
                )
            ],
            repairToolCall: repairFunction,
            system: nil,
            messages: []
        )

        // Verify invalid dynamic call with ToolCallRepairError
        guard case .dynamic(let dynamicCall) = result else {
            Issue.record("Expected dynamic tool call, got \(result)")
            return
        }

        #expect(dynamicCall.invalid == true)
        #expect(dynamicCall.title == "Test Tool")
        #expect(ToolCallRepairError.isInstance(dynamicCall.error!))
    }

    // MARK: - Dynamic Tool Tests

    @Test("should set dynamic to true for dynamic tools")
    func testSetsDynamicToTrueForDynamicTools() async throws {
        let result = await parseToolCall(
            toolCall: LanguageModelV3ToolCall(
                toolCallId: "123",
                toolName: "testTool",
                input: #"{"param1": "test", "param2": 42}"#
            ),
            tools: [
                "testTool": dynamicTool(
                    title: "Test Tool",
                    inputSchema: FlexibleSchema(
                        jsonSchema(
                            .object([
                                "type": .string("object"),
                                "properties": .object([
                                    "param1": .object(["type": .string("string")]),
                                    "param2": .object(["type": .string("number")]),
                                ]),
                                "required": .array([.string("param1"), .string("param2")]),
                                "additionalProperties": .bool(false),
                            ]))),
                    execute: { _, _ in .value(.string("result")) }
                )
            ],
            repairToolCall: nil,
            system: nil,
            messages: []
        )

        // Verify dynamic tool call
        guard case .dynamic(let dynamicCall) = result else {
            Issue.record("Expected dynamic tool call, got \(result)")
            return
        }

        #expect(dynamicCall.invalid == false)
        #expect(dynamicCall.toolCallId == "123")
        #expect(dynamicCall.toolName == "testTool")
        #expect(dynamicCall.title == "Test Tool")
        #expect(
            dynamicCall.input
                == JSONValue.object([
                    "param1": .string("test"),
                    "param2": .number(42),
                ]))
    }
}

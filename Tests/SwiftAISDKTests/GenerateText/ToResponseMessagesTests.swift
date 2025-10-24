/**
 Tests for toResponseMessages conversion helper.

 Port of `@ai-sdk/ai/src/generate-text/to-response-messages.test.ts`.
 */
import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("To Response Messages")
struct ToResponseMessagesTests {
    @Test("assistant message with text when no tool calls")
    func assistantMessageTextOnly() throws {
        let content: [ContentPart] = [
            .text(text: "Hello, world!", providerMetadata: nil)
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        #expect(result == [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .text(TextPart(text: "Hello, world!", providerOptions: nil))
                    ])
                )
            )
        ])
    }

    @Test("include tool calls in assistant message")
    func assistantMessageIncludesToolCall() throws {
        let toolCall = makeToolCall(
            id: "123",
            name: "testTool"
        )

        let content: [ContentPart] = [
            .text(text: "Using a tool", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil)
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .text(TextPart(text: "Using a tool", providerOptions: nil)),
                        .toolCall(
                            ToolCallPart(
                                toolCallId: "123",
                                toolName: "testTool",
                                input: toolCall.input,
                                providerOptions: nil,
                                providerExecuted: nil
                            )
                        )
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    @Test("include tool call metadata in assistant message")
    func assistantMessageIncludesToolCallMetadata() throws {
        let metadata: ProviderMetadata = [
            "testProvider": ["signature": .string("sig")]
        ]

        let toolCall = makeToolCall(
            id: "123",
            name: "testTool",
            providerMetadata: metadata
        )

        let content: [ContentPart] = [
            .text(text: "Using a tool", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: metadata)
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .text(TextPart(text: "Using a tool", providerOptions: nil)),
                        .toolCall(
                            ToolCallPart(
                                toolCallId: "123",
                                toolName: "testTool",
                                input: toolCall.input,
                                providerOptions: metadata,
                                providerExecuted: nil
                            )
                        )
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    @Test("include tool results as separate message")
    func toolResultsAsSeparateMessage() throws {
        let toolCall = makeToolCall(id: "123", name: "testTool")
        let toolResult = makeToolResult(
            id: "123",
            name: "testTool",
            output: .string("Tool result")
        )

        let content: [ContentPart] = [
            .text(text: "Tool used", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil),
            toolResult
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        let expectedAssistantContent: [AssistantContentPart] = [
            .text(TextPart(text: "Tool used", providerOptions: nil)),
            .toolCall(
                ToolCallPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    input: toolCall.input,
                    providerOptions: nil,
                    providerExecuted: nil
                )
            )
        ]

        let expectedToolContent: [ToolContentPart] = [
            .toolResult(
                ToolResultPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    output: .text(value: "Tool result")
                )
            )
        ]

        let expected: [ModelMessage] = [
            .assistant(AssistantModelMessage(content: .parts(expectedAssistantContent))),
            .tool(ToolModelMessage(content: expectedToolContent))
        ]

        #expect(result == expected)
    }

    @Test("include tool errors as separate message")
    func toolErrorsAsSeparateMessage() throws {
        let toolCall = makeToolCall(id: "123", name: "testTool")
        let toolError = makeToolError(
            id: "123",
            name: "testTool",
            error: TestError.message("Tool error")
        )

        let content: [ContentPart] = [
            .text(text: "Tool used", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil),
            toolError
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        let expectedAssistantContent: [AssistantContentPart] = [
            .text(TextPart(text: "Tool used", providerOptions: nil)),
            .toolCall(
                ToolCallPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    input: toolCall.input,
                    providerOptions: nil,
                    providerExecuted: nil
                )
            )
        ]

        let expectedToolContent: [ToolContentPart] = [
            .toolResult(
                ToolResultPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    output: .errorText(value: "Tool error")
                )
            )
        ]

        let expected: [ModelMessage] = [
            .assistant(AssistantModelMessage(content: .parts(expectedAssistantContent))),
            .tool(ToolModelMessage(content: expectedToolContent))
        ]

        #expect(result == expected)
    }

    @Test("handle reasoning content")
    func handleReasoningContent() throws {
        let metadata: ProviderMetadata = [
            "testProvider": ["signature": .string("sig")]
        ]

        let content: [ContentPart] = [
            .reasoning(ReasoningOutput(text: "Thinking text", providerMetadata: metadata))
        ]

        let result = toResponseMessages(content: content, tools: [:])

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .reasoning(
                            ReasoningPart(text: "Thinking text", providerOptions: metadata)
                        )
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    @Test("handle reasoning array with redacted reasoning")
    func handleRedactedReasoning() throws {
        let redacted: ProviderMetadata = ["testProvider": ["isRedacted": .bool(true)]]
        let metadata: ProviderMetadata = ["testProvider": ["signature": .string("sig")]]

        let content: [ContentPart] = [
            .reasoning(ReasoningOutput(text: "redacted-data", providerMetadata: redacted)),
            .reasoning(ReasoningOutput(text: "Thinking text", providerMetadata: metadata)),
            .text(text: "Final text", providerMetadata: nil)
        ]

        let result = toResponseMessages(content: content, tools: [:])

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .reasoning(ReasoningPart(text: "redacted-data", providerOptions: redacted)),
                        .reasoning(ReasoningPart(text: "Thinking text", providerOptions: metadata)),
                        .text(TextPart(text: "Final text", providerOptions: nil))
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    @Test("handle tool toModelOutput override")
    func toolToModelOutputOverride() throws {
        let toolCall = makeToolCall(id: "123", name: "testTool")
        let toolResult = makeToolResult(
            id: "123",
            name: "testTool",
            output: .string("image-base64")
        )

        let tools: ToolSet = [
            "testTool": Tool(
                description: "A test tool",
                providerOptions: nil,
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: nil,
                onInputStart: nil,
                onInputDelta: nil,
                onInputAvailable: nil,
                execute: nil,
                outputSchema: nil,
                toModelOutput: { _ in
                    LanguageModelV3ToolResultOutput.json(
                        value: .object(["proof": .string("that toModelOutput is called")])
                    )
                },
                type: nil,
                id: nil,
                name: nil,
                args: nil
            )
        ]

        let content: [ContentPart] = [
            .text(text: "multipart tool result", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil),
            toolResult
        ]

        let result = toResponseMessages(content: content, tools: tools)

        let expectedToolContent: [ToolContentPart] = [
            .toolResult(
                ToolResultPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    output: .json(value: .object(["proof": .string("that toModelOutput is called")]))
                )
            )
        ]

        #expect(result.last == .tool(ToolModelMessage(content: expectedToolContent)))
    }

    @Test("include images in assistant message")
    func includeImagesInAssistantMessage() throws {
        let pngData = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let pngFile = DefaultGeneratedFileWithType(data: pngData, mediaType: "image/png")

        let content: [ContentPart] = [
            .text(text: "Here is an image", providerMetadata: nil),
            .file(file: pngFile, providerMetadata: nil)
        ]

        let result = toResponseMessages(content: content, tools: [:])

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .text(TextPart(text: "Here is an image", providerOptions: nil)),
                        .file(
                            FilePart(
                                data: .string(pngFile.base64),
                                mediaType: pngFile.mediaType,
                                providerOptions: nil
                            )
                        )
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    @Test("handle multiple images")
    func handleMultipleImages() throws {
        let pngFile = DefaultGeneratedFileWithType(data: Data([137, 80, 78, 71, 13, 10, 26, 10]), mediaType: "image/png")
        let jpegFile = DefaultGeneratedFileWithType(data: Data([255, 216, 255]), mediaType: "image/jpeg")

        let content: [ContentPart] = [
            .text(text: "Here are multiple images", providerMetadata: nil),
            .file(file: pngFile, providerMetadata: nil),
            .file(file: jpegFile, providerMetadata: nil)
        ]

        let result = toResponseMessages(content: content, tools: [:])

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .text(TextPart(text: "Here are multiple images", providerOptions: nil)),
                        .file(FilePart(data: .string(pngFile.base64), mediaType: pngFile.mediaType, providerOptions: nil)),
                        .file(FilePart(data: .string(jpegFile.base64), mediaType: jpegFile.mediaType, providerOptions: nil))
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    @Test("include images reasoning and tool calls in order")
    func includeImagesReasoningAndToolCalls() throws {
        let pngFile = DefaultGeneratedFileWithType(data: Data([137, 80, 78, 71, 13, 10, 26, 10]), mediaType: "image/png")
        let toolCall = makeToolCall(id: "123", name: "testTool")
        let reasoningMetadata: ProviderMetadata = ["testProvider": ["signature": .string("sig")]]

        let content: [ContentPart] = [
            .reasoning(ReasoningOutput(text: "Thinking text", providerMetadata: reasoningMetadata)),
            .file(file: pngFile, providerMetadata: nil),
            .text(text: "Combined response", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil)
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        let expectedAssistantContent: [AssistantContentPart] = [
            .reasoning(ReasoningPart(text: "Thinking text", providerOptions: reasoningMetadata)),
            .file(FilePart(data: .string(pngFile.base64), mediaType: pngFile.mediaType, providerOptions: nil)),
            .text(TextPart(text: "Combined response", providerOptions: nil)),
            .toolCall(
                ToolCallPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    input: toolCall.input,
                    providerOptions: nil,
                    providerExecuted: nil
                )
            )
        ]

        #expect(result == [
            .assistant(AssistantModelMessage(content: .parts(expectedAssistantContent)))
        ])
    }

    @Test("skip empty text parts")
    func skipEmptyTextParts() throws {
        let toolCall = makeToolCall(id: "123", name: "testTool")
        let content: [ContentPart] = [
            .text(text: "", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil)
        ]

        let tools = makeToolSet()
        let result = toResponseMessages(content: content, tools: tools)

        let expectedAssistantContent: [AssistantContentPart] = [
            .toolCall(
                ToolCallPart(
                    toolCallId: "123",
                    toolName: "testTool",
                    input: toolCall.input,
                    providerOptions: nil,
                    providerExecuted: nil
                )
            )
        ]

        #expect(result == [
            .assistant(AssistantModelMessage(content: .parts(expectedAssistantContent)))
        ])
    }

    @Test("return empty array without content")
    func emptyContentReturnsEmptyArray() throws {
        let result = toResponseMessages(content: [], tools: [:])
        #expect(result.isEmpty)
    }

    @Test("include provider-executed tool calls and results")
    func providerExecutedToolCalls() throws {
        let queryValue = JSONValue.string("San Francisco major news events June 22 2025")
        let toolCall = makeToolCall(
            id: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
            name: "web_search",
            input: .object(["query": queryValue]),
            providerExecuted: true
        )
        let toolResult = makeToolResult(
            id: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
            name: "web_search",
            output: .array([
                .object(["url": .string("https://patch.com/california/san-francisco/calendar")])
            ]),
            providerExecuted: true
        )

        let content: [ContentPart] = [
            .text(text: "Let me search for recent news from San Francisco.", providerMetadata: nil),
            .toolCall(toolCall, providerMetadata: nil),
            toolResult,
            .text(
                text: "Based on the search results, several significant events took place in San Francisco yesterday (June 22, 2025). Here are the main highlights:\n\n1. Juneteenth Celebration:\n",
                providerMetadata: nil
            )
        ]

        let providerDefinedTool = Tool(
            description: nil,
            providerOptions: nil,
            inputSchema: FlexibleSchema(jsonSchema(.object(["query": .object(["type": .string("string")])]))),
            needsApproval: nil,
            onInputStart: nil,
            onInputDelta: nil,
            onInputAvailable: nil,
            execute: nil,
            outputSchema: nil,
            toModelOutput: nil,
            type: .providerDefined,
            id: "test.web_search",
            name: "web_search",
            args: [:]
        )

        let tools: ToolSet = ["web_search": providerDefinedTool]

        let result = toResponseMessages(content: content, tools: tools)

        #expect(result.count == 1)
        let assistantMessage = result.first!
        guard case .assistant(let message) = assistantMessage else {
            Issue.record("Expected assistant message")
            return
        }
        let expectedOutput = LanguageModelV3ToolResultOutput.json(
            value: .array([
                .object(["url": .string("https://patch.com/california/san-francisco/calendar")])
            ])
        )
        #expect(message.content == .parts([
            .text(TextPart(text: "Let me search for recent news from San Francisco.", providerOptions: nil)),
            .toolCall(
                ToolCallPart(
                    toolCallId: toolCall.toolCallId,
                    toolName: toolCall.toolName,
                    input: toolCall.input,
                    providerOptions: nil,
                    providerExecuted: true
                )
            ),
            .toolResult(
                ToolResultPart(
                    toolCallId: "srvtoolu_011cNtbtzFARKPcAcp7w4nh9",
                    toolName: "web_search",
                    output: expectedOutput,
                    providerOptions: nil
                )
            ),
            .text(TextPart(text: "Based on the search results, several significant events took place in San Francisco yesterday (June 22, 2025). Here are the main highlights:\n\n1. Juneteenth Celebration:\n", providerOptions: nil))
        ]))
    }

    @Test("include provider metadata in text parts")
    func includeProviderMetadataInText() throws {
        let metadata: ProviderMetadata = ["testProvider": ["signature": .string("sig")]]
        let content: [ContentPart] = [
            .text(text: "Here is a text", providerMetadata: metadata)
        ]

        let result = toResponseMessages(content: content, tools: [:])

        let expected: [ModelMessage] = [
            .assistant(
                AssistantModelMessage(
                    content: .parts([
                        .text(TextPart(text: "Here is a text", providerOptions: metadata))
                    ])
                )
            )
        ]

        #expect(result == expected)
    }

    // MARK: - Helpers

    private func makeToolSet() -> ToolSet {
        [
            "testTool": tool(
                description: "A test tool",
                providerOptions: nil,
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                execute: nil,
                outputSchema: nil,
                toModelOutput: nil
            )
        ]
    }

    private func makeToolCall(
        id: String,
        name: String,
        input: JSONValue = .object([:]),
        providerMetadata: ProviderMetadata? = nil,
        providerExecuted: Bool? = nil
    ) -> TypedToolCall {
        .static(
            StaticToolCall(
                toolCallId: id,
                toolName: name,
                input: input,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata
            )
        )
    }

    private func makeToolResult(
        id: String,
        name: String,
        output: JSONValue,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) -> ContentPart {
        let result = StaticToolResult(
            toolCallId: id,
            toolName: name,
            input: .object([:]),
            output: output,
            providerExecuted: providerExecuted
        )
        return .toolResult(.static(result), providerMetadata: providerMetadata)
    }

    private func makeToolError(
        id: String,
        name: String,
        error: any Error,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) -> ContentPart {
        let result = StaticToolError(
            toolCallId: id,
            toolName: name,
            input: .object([:]),
            error: error,
            providerExecuted: providerExecuted
        )
        return .toolError(.static(result), providerMetadata: providerMetadata)
    }
}

private enum TestError: Error, CustomStringConvertible, LocalizedError {
    case message(String)

    var description: String {
        switch self {
        case .message(let value):
            return value
        }
    }

    var errorDescription: String? {
        description
    }
}

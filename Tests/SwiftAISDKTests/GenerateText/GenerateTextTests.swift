/**
 Tests for the non-streaming generateText entry point.

 Port of `@ai-sdk/ai/src/generate-text/generate-text.test.ts`.
 */

import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateText Tests")
struct GenerateTextTests {
    // MARK: - Shared Fixtures

    private let testUsage = LanguageModelUsage(
        inputTokens: 3,
        outputTokens: 10,
        totalTokens: 13
    )

    private func makeGenerateResult(
        content: [LanguageModelV3Content],
        finishReason: LanguageModelV3FinishReason = .stop,
        usage: LanguageModelUsage? = nil,
        warnings: [LanguageModelV3CallWarning] = [],
        providerMetadata: ProviderMetadata? = nil,
        request: LanguageModelV3RequestInfo? = nil,
        response: LanguageModelV3ResponseInfo? = nil
    ) -> LanguageModelV3GenerateResult {
        LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage ?? testUsage,
            providerMetadata: providerMetadata,
            request: request,
            response: response,
            warnings: warnings
        )
    }

    private func toolInputSchema(requiredKey: String = "value") -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(toolSchemaJSON(requiredKey: requiredKey))
        )
    }

    private func mockId(prefix: String = "id") -> IDGenerator {
        let counter = IDCounter(prefix: prefix)
        return { counter.next() }
    }

    private func makeTool(
        execute: @escaping @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>
    ) -> Tool {
        tool(
            inputSchema: toolInputSchema(),
            execute: execute
        )
    }

    private func toolSchemaJSON(requiredKey: String) -> JSONValue {
        .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                requiredKey: .object([
                    "type": .string("string")
                ])
            ]),
            "required": .array([.string(requiredKey)]),
            "additionalProperties": .bool(false)
        ])
    }

    private func makeToolCallContent(
        toolCallId: String,
        toolName: String,
        input: String,
        providerExecuted: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) -> LanguageModelV3Content {
        .toolCall(
            LanguageModelV3ToolCall(
                toolCallId: toolCallId,
                toolName: toolName,
                input: input,
                providerExecuted: providerExecuted,
                providerMetadata: providerMetadata
            )
        )
    }

    private func makeToolResultContent(
        toolCallId: String,
        toolName: String,
        result: JSONValue,
        isError: Bool? = nil,
        providerExecuted: Bool? = nil,
        preliminary: Bool? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) -> LanguageModelV3Content {
        .toolResult(
            LanguageModelV3ToolResult(
                toolCallId: toolCallId,
                toolName: toolName,
                result: result,
                isError: isError,
                providerExecuted: providerExecuted,
                preliminary: preliminary,
                providerMetadata: providerMetadata
            )
        )
    }

    private func textContent(
        _ text: String,
        providerMetadata: ProviderMetadata? = nil
    ) -> LanguageModelV3Content {
        .text(LanguageModelV3Text(text: text, providerMetadata: providerMetadata))
    }

    private func reasoningContent(
        _ text: String,
        providerMetadata: ProviderMetadata? = nil
    ) -> LanguageModelV3Content {
        .reasoning(LanguageModelV3Reasoning(text: text, providerMetadata: providerMetadata))
    }

    private func fileContent(
        mediaType: String,
        data: LanguageModelV3FileData
    ) -> LanguageModelV3Content {
        .file(LanguageModelV3File(mediaType: mediaType, data: data))
    }

    private func urlSourceContent(
        id: String,
        url: String,
        title: String? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) -> LanguageModelV3Content {
        .source(
            .url(
                id: id,
                url: url,
                title: title,
                providerMetadata: providerMetadata
            )
        )
    }

    private func makeModelWithSources() -> MockLanguageModelV3 {
        MockLanguageModelV3(
            doGenerate: .singleValue(
                makeGenerateResult(
                    content: [
                        textContent("Hello, world!"),
                        urlSourceContent(
                            id: "123",
                            url: "https://example.com",
                            title: "Example",
                            providerMetadata: ["provider": ["custom": .string("value")]]
                        ),
                        urlSourceContent(
                            id: "456",
                            url: "https://example.com/2",
                            title: "Example 2",
                            providerMetadata: ["provider": ["custom": .string("value2")]]
                        )
                    ]
                )
            )
        )
    }

    private func makeModelWithFiles() -> MockLanguageModelV3 {
        MockLanguageModelV3(
            doGenerate: .singleValue(
                makeGenerateResult(
                    content: [
                        textContent("Hello, world!"),
                        fileContent(
                            mediaType: "image/png",
                            data: .binary(Data([1, 2, 3]))
                        ),
                        fileContent(
                            mediaType: "image/jpeg",
                            data: .base64("QkFVRw==")
                        )
                    ]
                )
            )
        )
    }

    private func makeModelWithReasoning() -> MockLanguageModelV3 {
        MockLanguageModelV3(
            doGenerate: .singleValue(
                makeGenerateResult(
                    content: [
                        reasoningContent(
                            "I will open the conversation with witty banter.",
                            providerMetadata: [
                                "testProvider": ["signature": .string("signature")]
                            ]
                        ),
                        reasoningContent(
                            "",
                            providerMetadata: [
                                "testProvider": ["redactedData": .string("redacted-reasoning-data")]
                            ]
                        ),
                        textContent("Hello, world!")
                    ]
                )
            )
        )
    }

    // MARK: - result.content

    @Test("result.content contains generated content and tool results")
    func resultGeneratesContent() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                makeGenerateResult(
                    content: [
                        textContent("Hello, world!"),
                        urlSourceContent(
                            id: "123",
                            url: "https://example.com",
                            title: "Example",
                            providerMetadata: ["provider": ["custom": .string("value")]]
                        ),
                        fileContent(
                            mediaType: "image/png",
                            data: .binary(Data([1, 2, 3]))
                        ),
                        reasoningContent("I will open the conversation with witty banter."),
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "tool1",
                            input: #"{ "value": "value" }"#
                        ),
                        textContent("More text")
                    ]
                )
            )
        )

        let executeRecorder = ValueRecorder<JSONValue>()

        let tools: ToolSet = [
            "tool1": makeTool { args, _ in
                await executeRecorder.append(args)
                return .value(JSONValue.string("result1"))
            }
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "prompt"
        )

        let executeCalls = await executeRecorder.entries()
        #expect(executeCalls.count == 1)
        if case .object(let value) = executeCalls.first {
            #expect(value["value"] == JSONValue.string("value"))
        } else {
            Issue.record("Expected JSON object for tool input")
        }

        #expect(result.content.count == 7)

        if case .text(let text, _) = result.content[0] {
            #expect(text == "Hello, world!")
        } else {
            Issue.record("Expected first content part to be text")
        }

        if case .source(_, let source) = result.content[1] {
            switch source {
            case .url(let id, let url, let title, let metadata):
                #expect(id == "123")
                #expect(url == "https://example.com")
                #expect(title == "Example")
                #expect(metadata?["provider"]?["custom"] == JSONValue.string("value"))
            default:
                Issue.record("Expected URL source")
            }
        } else {
            Issue.record("Expected second content part to be source")
        }

        if case .file(let generatedFile, _) = result.content[2] {
            #expect(generatedFile.mediaType == "image/png")
            #expect(generatedFile.data == Data([1, 2, 3]))
        } else {
            Issue.record("Expected third content part to be file")
        }

        if case .reasoning(let reasoning) = result.content[3] {
            #expect(reasoning.text == "I will open the conversation with witty banter.")
        } else {
            Issue.record("Expected fourth content part to be reasoning")
        }

        if case .toolCall(let toolCall, _) = result.content[4] {
            #expect(toolCall.toolCallId == "call-1")
            #expect(toolCall.toolName == "tool1")
            #expect(toolCall.input == JSONValue.object(["value": .string("value")]))
        } else {
            Issue.record("Expected fifth content part to be tool call")
        }

        if case .text(let moreText, _) = result.content[5] {
            #expect(moreText == "More text")
        } else {
            Issue.record("Expected sixth content part to be text")
        }

        if case .toolResult(let toolResult, _) = result.content[6] {
            #expect(toolResult.toolCallId == "call-1")
            #expect(toolResult.toolName == "tool1")
            #expect(toolResult.output == JSONValue.string("result1"))
        } else {
            Issue.record("Expected seventh content part to be tool result")
        }
    }

    // MARK: - result.text

    @Test("result.text returns generated text")
    func resultTextReturnsGeneratedText() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                makeGenerateResult(
                    content: [
                        textContent("Hello, world!")
                    ]
                )
            )
        )

        let referenceModel = makeModelWithSources()

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt"
        )

        #expect(result.text == "Hello, world!")
        #expect(referenceModel.doGenerateCalls.isEmpty)
        #expect(model.doGenerateCalls.count == 1)
    }

    // MARK: - result.reasoningText

    @Test("result.reasoningText contains reasoning string from model response")
    func resultReasoningTextContainsReasoning() async throws {
        let model = makeModelWithReasoning()

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt"
        )

        #expect(result.reasoningText == "I will open the conversation with witty banter.")
    }

    // MARK: - result.sources

    @Test("result.sources contains sources from model response")
    func resultSourcesContainsSources() async throws {
        let model = makeModelWithSources()

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt"
        )

        let sources = result.sources
        #expect(sources.count == 2)

        if case .url(let id, let url, let title, let metadata) = sources[0] {
            #expect(id == "123")
            #expect(url == "https://example.com")
            #expect(title == "Example")
            #expect(metadata?["provider"]?["custom"] == JSONValue.string("value"))
        } else {
            Issue.record("Expected first source to be URL")
        }

        if case .url(let id, let url, let title, let metadata) = sources[1] {
            #expect(id == "456")
            #expect(url == "https://example.com/2")
            #expect(title == "Example 2")
            #expect(metadata?["provider"]?["custom"] == JSONValue.string("value2"))
        } else {
            Issue.record("Expected second source to be URL")
        }
    }

    // MARK: - result.files

    @Test("result.files contains generated files")
    func resultFilesContainsFiles() async throws {
        let model = makeModelWithFiles()

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt"
        )

        let files = result.files
        #expect(files.count == 2)

        #expect(files[0].mediaType == "image/png")
        #expect(files[0].data == Data([1, 2, 3]))

        #expect(files[1].mediaType == "image/jpeg")
        #expect(files[1].base64 == "QkFVRw==")
    }

    // MARK: - result.steps

    @Test("result.steps includes reasoning output from model response")
    func resultStepsIncludeReasoning() async throws {
        let model = makeModelWithReasoning()
        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt",
            internalOptions: GenerateTextInternalOptions(
                generateId: mockId(),
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )

        let steps = result.steps
        #expect(steps.count == 1)

        guard let step = steps.first else {
            Issue.record("Expected at least one step")
            return
        }

        #expect(step.text == "Hello, world!")
        #expect(step.reasoningText == "I will open the conversation with witty banter.")
        #expect(step.reasoning.count == 2)
        #expect(step.finishReason == .stop)

        if step.reasoning.count >= 1 {
            let first = step.reasoning[0]
            #expect(first.text == "I will open the conversation with witty banter.")
            #expect(first.providerMetadata?["testProvider"]?["signature"] == JSONValue.string("signature"))
        }

        if step.reasoning.count >= 2 {
            let second = step.reasoning[1]
            #expect(second.text.isEmpty)
            #expect(second.providerMetadata?["testProvider"]?["redactedData"] == JSONValue.string("redacted-reasoning-data"))
        }

        #expect(step.content.count == 3)
        if case .reasoning(let reasoning) = step.content[0] {
            #expect(reasoning.text == "I will open the conversation with witty banter.")
        } else {
            Issue.record("Expected first step content to be reasoning")
        }

        if case .reasoning(let reasoning) = step.content[1] {
            #expect(reasoning.text.isEmpty)
        } else {
            Issue.record("Expected second step content to be reasoning")
        }

        if case .text(let text, _) = step.content[2] {
            #expect(text == "Hello, world!")
        } else {
            Issue.record("Expected third step content to be text")
        }
    }

    @Test("result.steps includes sources from model response")
    func resultStepsIncludeSources() async throws {
        let model = makeModelWithSources()
        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt",
            internalOptions: GenerateTextInternalOptions(
                generateId: mockId(),
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )

        let steps = result.steps
        #expect(steps.count == 1)

        guard let step = steps.first else {
            Issue.record("Expected at least one step")
            return
        }

        let sources = step.sources
        #expect(sources.count == 2)

        if case .url(let id, let url, let title, _) = sources[0] {
            #expect(id == "123")
            #expect(url == "https://example.com")
            #expect(title == "Example")
        } else {
            Issue.record("Expected first step source to be URL")
        }

        if case .url(let id, let url, let title, _) = sources[1] {
            #expect(id == "456")
            #expect(url == "https://example.com/2")
            #expect(title == "Example 2")
        } else {
            Issue.record("Expected second step source to be URL")
        }
    }

    @Test("result.steps includes files from model response")
    func resultStepsIncludeFiles() async throws {
        let model = makeModelWithFiles()
        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt",
            internalOptions: GenerateTextInternalOptions(
                generateId: mockId(),
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )

        let steps = result.steps
        #expect(steps.count == 1)

        guard let step = steps.first else {
            Issue.record("Expected at least one step")
            return
        }

        let files = step.files
        #expect(files.count == 2)
        #expect(files[0].mediaType == "image/png")
        #expect(files[0].data == Data([1, 2, 3]))
        #expect(files[1].mediaType == "image/jpeg")
        #expect(files[1].base64 == "QkFVRw==")
    }

    // MARK: - result.toolCalls

    @Test("result.toolCalls contains tool calls")
    func resultToolCallsContainsToolCalls() async throws {
        let expectedSchemaValue = toolSchemaJSON(requiredKey: "value")
        let expectedSchemaOther = toolSchemaJSON(requiredKey: "somethingElse")

        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                if let tools = options.tools {
                    #expect(tools.count == 2)

                    if tools.count >= 1, case .function(let functionTool) = tools[0] {
                        #expect(functionTool.name == "tool1")
                        #expect(functionTool.description == nil)
                        #expect(functionTool.inputSchema == expectedSchemaValue)
                        #expect(functionTool.providerOptions == nil)
                    } else {
                        Issue.record("Expected first tool to be function tool1")
                    }

                    if tools.count >= 2, case .function(let functionTool) = tools[1] {
                        #expect(functionTool.name == "tool2")
                        #expect(functionTool.description == nil)
                        #expect(functionTool.inputSchema == expectedSchemaOther)
                        #expect(functionTool.providerOptions == nil)
                    } else {
                        Issue.record("Expected second tool to be function tool2")
                    }
                } else {
                    Issue.record("Expected tools to be provided")
                }

                #expect(options.toolChoice == .required)

                let expectedPrompt: LanguageModelV3Prompt = [
                    .user(
                        content: [.text(LanguageModelV3TextPart(text: "test-input", providerOptions: nil))],
                        providerOptions: nil
                    )
                ]
                #expect(options.prompt == expectedPrompt)

                return LanguageModelV3GenerateResult(
                    content: [
                        LanguageModelV3Content.toolCall(
                            LanguageModelV3ToolCall(
                                toolCallId: "call-1",
                                toolName: "tool1",
                                input: #"{ "value": "value" }"#
                            )
                        )
                    ],
                    finishReason: .stop,
                    usage: testUsage
                )
            }
        )

        let tools: ToolSet = [
            "tool1": tool(inputSchema: toolInputSchema()),
            "tool2": tool(inputSchema: toolInputSchema(requiredKey: "somethingElse"))
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            toolChoice: .required,
            prompt: "test-input"
        )

        let toolCalls = result.toolCalls
        #expect(toolCalls.count == 1)

        let toolCall = toolCalls[0]
        #expect(toolCall.toolCallId == "call-1")
        #expect(toolCall.toolName == "tool1")
        #expect(toolCall.providerExecuted != true)
        #expect(toolCall.isDynamic == false)
        #expect(toolCall.input == JSONValue.object(["value": .string("value")]))
    }

    // MARK: - result.toolResults

    @Test("result.toolResults contains tool results")
    func resultToolResultsContainsToolResults() async throws {
        let expectedSchemaValue = toolSchemaJSON(requiredKey: "value")

        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                if let tools = options.tools {
                    #expect(tools.count == 1)

                    if tools.count == 1, case .function(let functionTool) = tools[0] {
                        #expect(functionTool.name == "tool1")
                        #expect(functionTool.inputSchema == expectedSchemaValue)
                    } else {
                        Issue.record("Expected single function tool")
                    }
                } else {
                    Issue.record("Expected tools to be provided")
                }

                #expect(options.toolChoice == .auto)

                let expectedPrompt: LanguageModelV3Prompt = [
                    .user(
                        content: [.text(LanguageModelV3TextPart(text: "test-input", providerOptions: nil))],
                        providerOptions: nil
                    )
                ]
                #expect(options.prompt == expectedPrompt)

                return LanguageModelV3GenerateResult(
                    content: [
                        LanguageModelV3Content.toolCall(
                            LanguageModelV3ToolCall(
                                toolCallId: "call-1",
                                toolName: "tool1",
                                input: #"{ "value": "value" }"#
                            )
                        )
                    ],
                    finishReason: .stop,
                    usage: testUsage
                )
            }
        )

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { args, options in
                    #expect(args == JSONValue.object(["value": .string("value")]))
                    #expect(options.messages.count == 1)
                    return .value(JSONValue.string("result1"))
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input"
        )

        let toolResults = result.toolResults
        #expect(toolResults.count == 1)

        let toolResult = toolResults[0]
        #expect(toolResult.toolCallId == "call-1")
        #expect(toolResult.toolName == "tool1")
        #expect(toolResult.providerExecuted == nil)
        #expect(toolResult.isDynamic == false)
        #expect(toolResult.output == JSONValue.string("result1"))
        #expect(toolResult.input == JSONValue.object(["value": .string("value")]))
    }

    // MARK: - result.providerMetadata

    @Test("result.providerMetadata contains provider metadata")
    func resultProviderMetadataContainsMetadata() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [],
                    finishReason: .stop,
                    usage: testUsage,
                    providerMetadata: [
                        "exampleProvider": [
                            "a": .number(10),
                            "b": .number(20)
                        ]
                    ]
                )
            )
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "test-input"
        )

        let metadata = result.providerMetadata
        #expect(metadata?["exampleProvider"]?["a"] == JSONValue.number(10))
        #expect(metadata?["exampleProvider"]?["b"] == JSONValue.number(20))
    }

    // MARK: - result.response.messages

    @Test("result.response.messages contains assistant response when no tool calls")
    func resultResponseMessagesWithoutToolCalls() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                makeGenerateResult(
                    content: [
                        textContent("Hello, world!")
                    ]
                )
            )
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "test-input"
        )

        let messages = result.response.messages
        #expect(messages.count == 1)

        guard case .assistant(let assistantMessage) = messages.first else {
            Issue.record("Expected assistant message")
            return
        }

        switch assistantMessage.content {
        case .text(let text):
            #expect(text == "Hello, world!")
        case .parts(let parts):
            #expect(parts.count == 1)
            if case .text(let textPart) = parts.first {
                #expect(textPart.text == "Hello, world!")
            } else {
                Issue.record("Expected text part in assistant message")
            }
        }
    }

    @Test("result.response.messages contains assistant and tool messages when tool results exist")
    func resultResponseMessagesWithToolResults() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .function { _ in
                LanguageModelV3GenerateResult(
                    content: [
                        textContent("Hello, world!"),
                        LanguageModelV3Content.toolCall(
                            LanguageModelV3ToolCall(
                                toolCallId: "call-1",
                                toolName: "tool1",
                                input: #"{ "value": "value" }"#
                            )
                        )
                    ],
                    finishReason: .stop,
                    usage: testUsage
                )
            }
        )

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { args, options in
                    #expect(args == JSONValue.object(["value": .string("value")]))
                    if options.messages.count == 1 {
                        if case .user(let userMessage) = options.messages[0] {
                            switch userMessage.content {
                            case .text(let text):
                                #expect(text == "test-input")
                            case .parts:
                                Issue.record("Expected text content in user message")
                            }
                        } else {
                            Issue.record("Expected user message in options.messages")
                        }
                    }
                    return .value(JSONValue.string("result1"))
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input"
        )

        let messages = result.response.messages
        #expect(messages.count == 2)

        guard case .assistant(let assistantMessage) = messages.first else {
            Issue.record("Expected first message to be assistant")
            return
        }

        switch assistantMessage.content {
        case .parts(let parts):
            #expect(parts.count == 2)
            if case .text(let textPart) = parts[0] {
                #expect(textPart.text == "Hello, world!")
            } else {
                Issue.record("Expected first assistant part to be text")
            }
            if case .toolCall(let toolCallPart) = parts[1] {
                #expect(toolCallPart.toolCallId == "call-1")
                #expect(toolCallPart.toolName == "tool1")
                #expect(toolCallPart.input == JSONValue.object(["value": .string("value")]))
                #expect(toolCallPart.providerExecuted == nil)
            } else {
                Issue.record("Expected second assistant part to be tool call")
            }
        case .text:
            Issue.record("Expected assistant message to contain parts")
        }

        guard case .tool(let toolMessage) = messages[1] else {
            Issue.record("Expected second message to be tool message")
            return
        }

        #expect(toolMessage.content.count == 1)
        if case .toolResult(let toolResultPart) = toolMessage.content[0] {
            #expect(toolResultPart.toolCallId == "call-1")
            #expect(toolResultPart.toolName == "tool1")
            if case .text(let output) = toolResultPart.output {
                #expect(output == "result1")
            } else {
                Issue.record("Expected tool result output to be text")
            }
        } else {
            Issue.record("Expected tool result part in tool message")
        }
    }

    @Test("result.response.messages contains reasoning parts")
    func resultResponseMessagesContainReasoning() async throws {
        let model = makeModelWithReasoning()

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "test-input"
        )

        let messages = result.response.messages
        #expect(messages.count == 1)

        guard case .assistant(let assistantMessage) = messages.first else {
            Issue.record("Expected assistant message")
            return
        }

        switch assistantMessage.content {
        case .parts(let parts):
            #expect(parts.count == 3)
            if case .reasoning(let reasoningPart) = parts[0] {
                #expect(reasoningPart.text == "I will open the conversation with witty banter.")
                #expect(reasoningPart.providerOptions?["testProvider"]?["signature"] == JSONValue.string("signature"))
            } else {
                Issue.record("Expected first part to be reasoning")
            }

            if case .reasoning(let reasoningPart) = parts[1] {
                #expect(reasoningPart.text.isEmpty)
                #expect(reasoningPart.providerOptions?["testProvider"]?["redactedData"] == JSONValue.string("redacted-reasoning-data"))
            } else {
                Issue.record("Expected second part to be reasoning")
            }

            if case .text(let textPart) = parts[2] {
                #expect(textPart.text == "Hello, world!")
            } else {
                Issue.record("Expected third part to be text")
            }
        case .text:
            Issue.record("Expected reasoning parts in assistant content")
        }
    }

    // MARK: - result.request

    @Test("result.request contains request body metadata")
    func resultRequestContainsBody() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .function { _ in
                LanguageModelV3GenerateResult(
                    content: [
                        textContent("Hello, world!")
                    ],
                    finishReason: .stop,
                    usage: testUsage,
                    request: LanguageModelV3RequestInfo(body: "test body")
                )
            }
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt"
        )

        #expect(result.request.body == JSONValue.string("test body"))
    }

    // MARK: - result.response

    @Test("result.response contains response metadata and body")
    func resultResponseContainsMetadata() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .function { _ in
                LanguageModelV3GenerateResult(
                    content: [
                        textContent("Hello, world!")
                    ],
                    finishReason: .stop,
                    usage: testUsage,
                    response: LanguageModelV3ResponseInfo(
                        id: "test-id-from-model",
                        timestamp: Date(timeIntervalSince1970: 10),
                        modelId: "test-response-model-id",
                        headers: ["custom-response-header": "response-header-value"],
                        body: "test body"
                    )
                )
            }
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            prompt: "prompt"
        )

        guard let step = result.steps.first else {
            Issue.record("Expected at least one step")
            return
        }

        let stepResponse = step.response
        #expect(stepResponse.id == "test-id-from-model")
        #expect(stepResponse.timestamp == Date(timeIntervalSince1970: 10))
        #expect(stepResponse.modelId == "test-response-model-id")
        #expect(stepResponse.headers?["custom-response-header"] == "response-header-value")
        #expect(stepResponse.body == JSONValue.string("test body"))

        let finalResponse = result.response
        #expect(finalResponse.id == "test-id-from-model")
        #expect(finalResponse.timestamp == Date(timeIntervalSince1970: 10))
        #expect(finalResponse.modelId == "test-response-model-id")
        #expect(finalResponse.headers?["custom-response-header"] == "response-header-value")
        #expect(finalResponse.body == JSONValue.string("test body"))
        #expect(finalResponse.messages == stepResponse.messages)
    }

    // MARK: - options.onFinish

    @Test("options.onFinish receives correct finish event payload")
    func optionsOnFinishReceivesCorrectPayload() async throws {
        let finishRecorder = ValueRecorder<GenerateTextFinishEvent>()

        let model = MockLanguageModelV3(
            doGenerate: .function { _ in
                LanguageModelV3GenerateResult(
                    content: [
                        textContent("Hello, World!"),
                        LanguageModelV3Content.toolCall(
                            LanguageModelV3ToolCall(
                                toolCallId: "call-1",
                                toolName: "tool1",
                                input: #"{ "value": "value" }"#
                            )
                        )
                    ],
                    finishReason: .stop,
                    usage: testUsage,
                    response: LanguageModelV3ResponseInfo(
                        id: "id-0",
                        timestamp: Date(timeIntervalSince1970: 0),
                        modelId: "mock-model-id",
                        headers: ["call": "2"]
                    )
                )
            }
        )

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { args, _ in
                    #expect(args == JSONValue.object(["value": .string("value")]))
                    return .value(JSONValue.string("value-result"))
                }
            )
        ]

        _ = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "irrelevant",
            onFinish: { event in
                await finishRecorder.append(event)
            }
        ) as DefaultGenerateTextResult<JSONValue>

        let captured = await finishRecorder.entries()
        guard let event = captured.first else {
            Issue.record("onFinish event was not captured")
            return
        }

        #expect(event.finishReason == .stop)
        #expect(event.usage == testUsage)
        #expect(event.text == "Hello, World!")
        #expect(event.reasoning.isEmpty)
        #expect(event.reasoningText == nil)
        #expect(event.files.isEmpty)
        #expect(event.sources.isEmpty)
        #expect(event.dynamicToolCalls.isEmpty)
        #expect(event.dynamicToolResults.isEmpty)

        #expect(event.toolCalls.count == 1)
        let call = event.toolCalls[0]
        #expect(call.toolCallId == "call-1")
        #expect(call.toolName == "tool1")
        #expect(call.input == JSONValue.object(["value": .string("value")]))

        #expect(event.toolResults.count == 1)
        let result = event.toolResults[0]
        #expect(result.toolCallId == "call-1")
        #expect(result.toolName == "tool1")
        #expect(result.output == JSONValue.string("value-result"))

        #expect(event.staticToolCalls.count == 1)
        #expect(event.staticToolResults.count == 1)
        #expect(event.dynamicToolCalls.isEmpty)
        #expect(event.dynamicToolResults.isEmpty)

        #expect(event.request.body == nil)

        #expect(event.response.id == "id-0")
        #expect(event.response.modelId == "mock-model-id")
        #expect(event.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(event.response.headers?["call"] == "2")

        #expect(event.providerMetadata == nil)
        #expect(event.warnings?.isEmpty ?? true)

        #expect(event.totalUsage == testUsage)

        let responseMessages = event.response.messages
        #expect(responseMessages.count == 2)
        if case .assistant(let assistantMessage) = responseMessages[0] {
            if case .parts(let parts) = assistantMessage.content {
                #expect(parts.count == 2)
            } else {
                Issue.record("Expected assistant message to contain parts")
            }
        } else {
            Issue.record("Expected assistant message as first response message")
        }

        if case .tool(let toolMessage) = responseMessages[1] {
            #expect(toolMessage.content.count == 1)
        } else {
            Issue.record("Expected tool message as second response message")
        }
    }

    // MARK: - options.stopWhen (two steps: initial, tool-result)

    @Test("stopWhen two-step result.text equals last step")
    func stopWhenTwoStepResultText() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        #expect(scenario.result.text == "Hello, world!")
    }

    @Test("stopWhen two-step result.toolCalls empty for last step")
    func stopWhenTwoStepToolCallsEmpty() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        #expect(scenario.result.toolCalls.isEmpty)
    }

    @Test("stopWhen two-step result.toolResults empty for last step")
    func stopWhenTwoStepToolResultsEmpty() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        #expect(scenario.result.toolResults.isEmpty)
    }

    @Test("stopWhen two-step response messages include all steps")
    func stopWhenTwoStepResponseMessages() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        let messages = scenario.result.response.messages
        #expect(messages.count == 3)

        if case .assistant(let firstAssistant) = messages[0] {
            if case .parts(let parts) = firstAssistant.content {
                #expect(parts.count == 1)
                if case .toolCall(let toolCallPart) = parts[0] {
                    #expect(toolCallPart.toolCallId == "call-1")
                } else {
                    Issue.record("Expected tool call part in first assistant message")
                }
            } else {
                Issue.record("Expected assistant parts in first message")
            }
        } else {
            Issue.record("Expected first message to be assistant")
        }

        if case .tool(let toolMessage) = messages[1] {
            #expect(toolMessage.content.count == 1)
        } else {
            Issue.record("Expected second message to be tool message")
        }

        if case .assistant(let secondAssistant) = messages[2] {
            switch secondAssistant.content {
            case .text(let text):
                #expect(text == "Hello, world!")
            case .parts(let parts):
                if case .text(let textPart) = parts.first {
                    #expect(textPart.text == "Hello, world!")
                } else {
                    Issue.record("Expected text part in final assistant message")
                }
            }
        } else {
            Issue.record("Expected third message to be assistant")
        }
    }

    @Test("stopWhen two-step totalUsage sums step usage")
    func stopWhenTwoStepTotalUsage() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        let usage = scenario.result.totalUsage
        #expect(usage.inputTokens == 13)
        #expect(usage.outputTokens == 15)
        #expect(usage.totalTokens == 28)
    }

    @Test("stopWhen two-step usage reflects final step usage")
    func stopWhenTwoStepFinalUsage() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        let usage = scenario.result.usage
        #expect(usage.inputTokens == 3)
        #expect(usage.outputTokens == 10)
        #expect(usage.totalTokens == 13)
    }

    @Test("stopWhen two-step steps include both intermediate and final results")
    func stopWhenTwoStepIncludesAllSteps() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        let steps = scenario.result.steps
        #expect(steps.count == 2)

        if let first = steps.first {
            #expect(first.finishReason == .toolCalls)
            #expect(first.toolCalls.count == 1)
            #expect(first.toolResults.count == 1)
            #expect(first.response.id == "test-id-1-from-model")
        }

        if let last = steps.last {
            #expect(last.finishReason == .stop)
            #expect(last.text == "Hello, world!")
            #expect(last.toolCalls.isEmpty)
            #expect(last.toolResults.isEmpty)
            #expect(last.response.id == "test-id-2-from-model")
        }
    }

    @Test("stopWhen two-step onFinish event includes aggregated information")
    func stopWhenTwoStepOnFinishEvent() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        guard let event = scenario.finishEvent else {
            Issue.record("Expected onFinish event")
            return
        }

        #expect(event.finishReason == .stop)
        #expect(event.text == "Hello, world!")
        #expect(event.totalUsage.inputTokens == 13)
        #expect(event.totalUsage.outputTokens == 15)
        #expect(event.totalUsage.totalTokens == 28)
        #expect(event.toolCalls.isEmpty)
        #expect(event.toolResults.isEmpty)
        #expect(event.steps.count == 2)
        #expect(event.response.id == "test-id-2-from-model")
        #expect(event.response.messages.count == 3)
    }

    @Test("stopWhen two-step onStepFinish called for each step")
    func stopWhenTwoStepOnStepFinish() async throws {
        let scenario = try await runTwoStepStopWhenScenario()
        #expect(scenario.stepSnapshots.count == 2)

        if scenario.stepSnapshots.count == 2 {
            let first = scenario.stepSnapshots[0]
            #expect(first.finishReason == .toolCalls)
            #expect(first.toolCallCount == 1)
            #expect(first.toolResultCount == 1)
            #expect(first.responseMessageRoles == ["assistant", "tool"])

            let second = scenario.stepSnapshots[1]
            #expect(second.finishReason == .stop)
            #expect(second.toolCallCount == 0)
            #expect(second.toolResultCount == 0)
            #expect(second.responseMessageRoles == ["assistant", "tool", "assistant"])
        }
    }
}

private final class IDCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private let prefix: String

    init(prefix: String) {
        self.prefix = prefix
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        let value = "\(prefix)-\(current)"
        current += 1
        return value
    }
}

private actor ValueRecorder<Value> {
    private var values: [Value] = []

    func append(_ value: Value) {
        values.append(value)
    }

    func entries() -> [Value] {
        values
    }
}

private actor IntCounter {
    private var value = 0

    func next() -> Int {
        let current = value
        value += 1
        return current
    }
}

private struct StepSnapshot: Sendable {
    let finishReason: FinishReason
    let text: String
    let toolCallCount: Int
    let toolResultCount: Int
    let usage: LanguageModelUsage
    let responseMessageRoles: [String]
}

private struct StopWhenScenario: Sendable {
    let result: DefaultGenerateTextResult<JSONValue>
    let finishEvent: GenerateTextFinishEvent?
    let stepSnapshots: [StepSnapshot]
}

private extension GenerateTextTests {
    func runTwoStepStopWhenScenario() async throws -> StopWhenScenario {
        let finishRecorder = ValueRecorder<GenerateTextFinishEvent>()
        let stepRecorder = ValueRecorder<StepSnapshot>()
        let counter = IntCounter()

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { args, options in
                    #expect(args == JSONValue.object(["value": .string("value")]))
                    if options.messages.count == 1 {
                        if case .user(let userMessage) = options.messages[0] {
                            switch userMessage.content {
                            case .text(let text):
                                #expect(text == "test-input")
                            case .parts:
                                Issue.record("Expected text user message")
                            }
                        }
                    }
                    return .value(JSONValue.string("result1"))
                }
            )
        ]

        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                let current = await counter.next()
                switch current {
                case 0:
                    if let tools = options.tools, tools.count == 1, case .function(let functionTool) = tools.first {
                        #expect(functionTool.name == "tool1")
                    }
                    #expect(options.toolChoice == .auto)

                    let expectedPrompt: LanguageModelV3Prompt = [
                        .user(
                            content: [.text(LanguageModelV3TextPart(text: "test-input", providerOptions: nil))],
                            providerOptions: nil
                        )
                    ]
                    #expect(options.prompt == expectedPrompt)

                    return LanguageModelV3GenerateResult(
                        content: [
                            LanguageModelV3Content.toolCall(
                                LanguageModelV3ToolCall(
                                    toolCallId: "call-1",
                                    toolName: "tool1",
                                    input: #"{ "value": "value" }"#
                                )
                            )
                        ],
                        finishReason: .toolCalls,
                        usage: LanguageModelV3Usage(
                            inputTokens: 10,
                            outputTokens: 5,
                            totalTokens: 15
                        ),
                        response: LanguageModelV3ResponseInfo(
                            id: "test-id-1-from-model",
                            timestamp: Date(timeIntervalSince1970: 0),
                            modelId: "test-response-model-id"
                        )
                    )
                case 1:
                    return LanguageModelV3GenerateResult(
                        content: [
                            textContent("Hello, world!")
                        ],
                        finishReason: .stop,
                        usage: testUsage,
                        response: LanguageModelV3ResponseInfo(
                            id: "test-id-2-from-model",
                            timestamp: Date(timeIntervalSince1970: 10),
                            modelId: "test-response-model-id",
                            headers: ["custom-response-header": "response-header-value"]
                        )
                    )
                default:
                    throw NSError(domain: "StopWhenScenario", code: 1, userInfo: nil)
                }
            }
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input",
            stopWhen: [stepCountIs(3)],
            onStepFinish: { step in
                let snapshot = StepSnapshot(
                    finishReason: step.finishReason,
                    text: step.text,
                    toolCallCount: step.toolCalls.count,
                    toolResultCount: step.toolResults.count,
                    usage: step.usage,
                    responseMessageRoles: step.response.messages.map { message in
                        switch message {
                        case .assistant: return "assistant"
                        case .tool: return "tool"
                        }
                    }
                )
                await stepRecorder.append(snapshot)
            },
            onFinish: { event in
                await finishRecorder.append(event)
            }
        )

        let finishEvent = await finishRecorder.entries().first
        let stepSnapshots = await stepRecorder.entries()

        return StopWhenScenario(result: result, finishEvent: finishEvent, stepSnapshots: stepSnapshots)
    }
}

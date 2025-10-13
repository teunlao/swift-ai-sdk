/**
 Additional generateText tests covering advanced scenarios.

 Port of selected suites from `@ai-sdk/ai/src/generate-text/generate-text.test.ts`.
 */

import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateText Advanced Tests")
struct GenerateTextAdvancedTests {
    private let testUsage = LanguageModelUsage(
        inputTokens: 3,
        outputTokens: 10,
        totalTokens: 13
    )

    // MARK: - Telemetry

    @Test("telemetry records successful tool call span")
    func telemetryRecordsSuccessfulToolCall() async throws {
        let tracer = MockTracer()

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { input, _ in
                    #expect(input == JSONValue.object(["value": .string("value")]))
                    return .value(.string("result1"))
                }
            )
        ]

        _ = try await generateText(
            model: .v3(
                MockLanguageModelV3(
                    doGenerate: .singleValue(
                        LanguageModelV3GenerateResult(
                            content: [
                                makeToolCallContent(
                                    toolCallId: "call-1",
                                    toolName: "tool1",
                                    input: #"{ "value": "value" }"#
                                )
                            ],
                            finishReason: .toolCalls,
                            usage: testUsage
                        )
                    )
                )
            ),
            tools: tools,
            toolChoice: .auto,
            prompt: "test-input",
            experimentalTelemetry: TelemetrySettings(
                isEnabled: true,
                tracer: tracer
            ),
            internalOptions: GenerateTextInternalOptions(
                generateId: { "test-id" },
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        ) as DefaultGenerateTextResult<JSONValue>

        let spans = tracer.spanRecords
        #expect(spans.count == 3)

        if spans.count >= 3 {
            let toolSpan = spans[2]
            #expect(toolSpan.name == "ai.toolCall")
            #expect(toolSpan.status == nil)
            #expect(toolSpan.attributes["ai.toolCall.id"] == .string("call-1"))
            #expect(toolSpan.attributes["ai.toolCall.name"] == .string("tool1"))
            #expect(toolSpan.attributes["ai.toolCall.args"] == .string(#"{"value":"value"}"#))
            #expect(toolSpan.attributes["ai.toolCall.result"] == .string(#""result1""#))
        }
    }

    @Test("telemetry records tool call error span")
    func telemetryRecordsToolCallError() async throws {
        let tracer = MockTracer()

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { _, _ in
                    throw ToolTestError.executionFailed
                }
            )
        ]

        _ = try? await generateText(
            model: .v3(
                MockLanguageModelV3(
                    doGenerate: .singleValue(
                        LanguageModelV3GenerateResult(
                            content: [
                                makeToolCallContent(
                                    toolCallId: "call-1",
                                    toolName: "tool1",
                                    input: #"{ "value": "value" }"#
                                )
                            ],
                            finishReason: .toolCalls,
                            usage: testUsage
                        )
                    )
                )
            ),
            tools: tools,
            toolChoice: .auto,
            prompt: "test-input",
            experimentalTelemetry: TelemetrySettings(
                isEnabled: true,
                tracer: tracer
            ),
            internalOptions: GenerateTextInternalOptions(
                generateId: { "test-id" },
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        ) as DefaultGenerateTextResult<JSONValue>

        let spans = tracer.spanRecords
        #expect(spans.count == 3)

        if spans.count >= 3 {
            let toolSpan = spans[2]
            #expect(toolSpan.name == "ai.toolCall")
            if let status = toolSpan.status {
                #expect(status.code == .error)
                #expect(status.message == "Tool execution failed")
            } else {
                Issue.record("Expected tool span status to be set")
            }

            if let event = toolSpan.events.first {
                #expect(event.name == "exception")
                if let attributes = event.attributes {
                    #expect(attributes["exception.message"] == .string("Tool execution failed"))
                    #expect(attributes["exception.type"] == .string("ToolTestError"))
                } else {
                    Issue.record("Expected exception attributes on telemetry event")
                }
            } else {
                Issue.record("Expected telemetry exception event")
            }
        }
    }

    // MARK: - Tool callbacks

    @Test("tool callbacks invoked in correct order")
    func toolCallbacksInvokedInOrder() async throws {
        let recorder = ValueRecorder<ToolCallbackRecord>()

        let tools: ToolSet = [
            "test-tool": tool(
                inputSchema: toolInputSchema(),
                onInputStart: { options in
                    await recorder.append(
                        ToolCallbackRecord(
                            type: .onInputStart,
                            toolCallId: options.toolCallId,
                            messageSummaries: summarizeMessages(options.messages),
                            input: nil,
                            inputTextDelta: nil
                        )
                    )
                },
                onInputDelta: { options in
                    await recorder.append(
                        ToolCallbackRecord(
                            type: .onInputDelta,
                            toolCallId: options.toolCallId,
                            messageSummaries: summarizeMessages(options.messages),
                            input: nil,
                            inputTextDelta: options.inputTextDelta
                        )
                    )
                },
                onInputAvailable: { options in
                    await recorder.append(
                        ToolCallbackRecord(
                            type: .onInputAvailable,
                            toolCallId: options.toolCallId,
                            messageSummaries: summarizeMessages(options.messages),
                            input: options.input,
                            inputTextDelta: nil
                        )
                    )
                },
                execute: { input, _ in
                    #expect(input == JSONValue.object(["value": .string("value")]))
                    return .value(.string("result1"))
                }
            )
        ]

        _ = try await generateText(
            model: .v3(
                MockLanguageModelV3(
                    doGenerate: .singleValue(
                        LanguageModelV3GenerateResult(
                            content: [
                                makeToolCallContent(
                                    toolCallId: "call-1",
                                    toolName: "test-tool",
                                    input: #"{ "value": "value" }"#
                                )
                            ],
                            finishReason: .toolCalls,
                            usage: testUsage
                        )
                    )
                )
            ),
            tools: tools,
            toolChoice: .required,
            prompt: "test-input"
        ) as DefaultGenerateTextResult<JSONValue>

        let records = await recorder.entries()
        #expect(records.count == 1)
        if let record = records.first {
            #expect(record.type == .onInputAvailable)
            #expect(record.toolCallId == "call-1")
            #expect(record.input == JSONValue.object(["value": .string("value")]))
            #expect(record.messageSummaries == ["user:text:test-input"])
            #expect(record.inputTextDelta == nil)
        }
    }

    // MARK: - Tools with custom schema

    @Test("tools with custom schema populate tool calls")
    func toolsWithCustomSchemaProducesCalls() async throws {
        var capturedTools: [LanguageModelV3Tool]?
        var capturedToolChoice: LanguageModelV3ToolChoice?
        var capturedPrompt: LanguageModelV3Prompt?

        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                capturedTools = options.tools
                capturedToolChoice = options.toolChoice
                capturedPrompt = options.prompt
                return LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "tool1",
                            input: #"{ "value": "value" }"#
                        )
                    ],
                    finishReason: .toolCalls,
                    usage: testUsage
                )
            }
        )

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(requiredKey: "value")
            ),
            "tool2": tool(
                inputSchema: FlexibleSchema(
                    jsonSchema(customToolSchema(requiredKey: "somethingElse"))
                )
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            toolChoice: .required,
            prompt: "test-input",
            internalOptions: GenerateTextInternalOptions(
                generateId: { "test-id" },
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )

        guard let capturedTools else {
            Issue.record("Expected tools to be forwarded to model")
            return
        }
        #expect(capturedTools.count == 2)
        if capturedTools.count == 2 {
            if case .function(let first) = capturedTools[0] {
                #expect(first.name == "tool1")
                #expect(first.inputSchema == toolSchemaJSON(requiredKey: "value"))
            } else {
                Issue.record("Expected first forwarded tool to be function tool1")
            }

            if case .function(let second) = capturedTools[1] {
                #expect(second.name == "tool2")
                #expect(second.inputSchema == customToolSchema(requiredKey: "somethingElse"))
            } else {
                Issue.record("Expected second forwarded tool to be function tool2")
            }
        }

        #expect(capturedToolChoice == .required)

        if let prompt = capturedPrompt {
            #expect(prompt.count == 1)
            if case .user(let userParts, _) = prompt.first {
                #expect(userParts.count == 1)
                if let firstPart = userParts.first, case .text(let textPart) = firstPart {
                    #expect(textPart.text == "test-input")
                } else {
                    Issue.record("Expected user text part in prompt")
                }
            } else {
                Issue.record("Expected user prompt entry")
            }
        } else {
            Issue.record("Expected prompt to be forwarded to model")
        }

        let toolCalls = result.toolCalls
        #expect(toolCalls.count == 1)
        if let call = toolCalls.first {
            #expect(call.toolCallId == "call-1")
            #expect(call.toolName == "tool1")
            #expect(call.input == JSONValue.object(["value": .string("value")]))
            #expect(call.providerExecuted == nil)
            #expect(call.providerMetadata == nil)
        }
    }

    // MARK: - Provider-executed tools

    @Test("provider-executed tools included in content")
    func providerExecutedToolsIncludedInContent() async throws {
        let scenario = try await runProviderExecutedToolsScenario()
        let content = scenario.result.content
        #expect(content.count == 4)

        if content.count == 4 {
            if case .toolCall(let firstCall, _) = content[0] {
                #expect(firstCall.toolCallId == "call-1")
                #expect(firstCall.toolName == "web_search")
                #expect(firstCall.providerExecuted == true)
                #expect(firstCall.input == JSONValue.object(["value": .string("value")]))
            } else {
                Issue.record("Expected first content entry to be provider-executed tool call")
            }

            if case .toolResult(let firstResult, _) = content[1] {
                if case .static(let staticResult) = firstResult {
                    #expect(staticResult.toolCallId == "call-1")
                    #expect(staticResult.toolName == "web_search")
                    #expect(staticResult.providerExecuted == true)
                    #expect(staticResult.output == JSONValue.string(#"{ "value": "result1" }"#))
                } else {
                    Issue.record("Expected static tool result for first provider result")
                }
            } else {
                Issue.record("Expected second content entry to be tool result")
            }

            if case .toolCall(let secondCall, _) = content[2] {
                #expect(secondCall.toolCallId == "call-2")
                #expect(secondCall.toolName == "web_search")
                #expect(secondCall.providerExecuted == true)
            } else {
                Issue.record("Expected third content entry to be provider-executed tool call")
            }

            if case .toolError(let errorResult, _) = content[3] {
                if case .static(let staticError) = errorResult {
                    #expect(staticError.toolCallId == "call-2")
                    #expect(staticError.toolName == "web_search")
                    #expect(staticError.providerExecuted == true)
                    #expect(staticError.input == JSONValue.object(["value": .string("value")]))
                    if let error = staticError.error as? LocalizedError {
                        #expect(error.errorDescription == "Provider tool execution error.")
                    }
                    #expect(String(describing: staticError.error) == #""ERROR""#)
                } else {
                    Issue.record("Expected static tool error result")
                }
            } else {
                Issue.record("Expected fourth content entry to be tool error")
            }
        }
    }

    @Test("provider-executed tools appear in static tool calls")
    func providerExecutedToolsIncludedInStaticCalls() async throws {
        let scenario = try await runProviderExecutedToolsScenario()
        let calls = scenario.result.staticToolCalls
        #expect(calls.count == 2)
        if calls.count == 2 {
            let first = calls[0]
            #expect(first.toolCallId == "call-1")
            #expect(first.toolName == "web_search")
            #expect(first.providerExecuted == true)

            let second = calls[1]
            #expect(second.toolCallId == "call-2")
            #expect(second.toolName == "web_search")
            #expect(second.providerExecuted == true)
        }
    }

    @Test("provider-executed results included in static tool results")
    func providerExecutedResultsIncludedInStaticResults() async throws {
        let scenario = try await runProviderExecutedToolsScenario()
        let results = scenario.result.staticToolResults
        #expect(results.count == 1)
        if let first = results.first {
            #expect(first.toolCallId == "call-1")
            #expect(first.toolName == "web_search")
            #expect(first.providerExecuted == true)
            #expect(first.output == JSONValue.string(#"{ "value": "result1" }"#))
        }
    }

    @Test("provider-executed tools produce single step")
    func providerExecutedToolsSingleStep() async throws {
        let scenario = try await runProviderExecutedToolsScenario()
        #expect(scenario.result.steps.count == 1)
    }

    @Test("provider-executed tools skip client execution")
    func providerExecutedToolsSkipClientExecution() async throws {
        let toolExecuted = Flag()

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "providerTool",
                            input: #"{ "value": "test" }"#,
                            providerExecuted: true
                        ),
                        makeToolResultContent(
                            toolCallId: "call-1",
                            toolName: "providerTool",
                            result: .object(["example": .string("example")]),
                            providerExecuted: true
                        )
                    ],
                    finishReason: .stop,
                    usage: testUsage
                )
            )
        )

        let tools: ToolSet = [
            "providerTool": tool(
                inputSchema: toolInputSchema(),
                execute: { _, _ in
                    await toolExecuted.set()
                    return .value(.string("should-not-execute"))
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input"
        )

        #expect(await toolExecuted.get() == false)

        let content = result.content
        #expect(content.count == 2)
        if content.count == 2 {
            if case .toolCall(let toolCall, _) = content[0] {
                #expect(toolCall.providerExecuted == true)
            }

            if case .toolResult(let resultPart, _) = content[1] {
                if case .static(let staticResult) = resultPart {
                    #expect(staticResult.providerExecuted == true)
                    #expect(staticResult.output == .object(["example": .string("example")]))
                }
            }
        }

        let toolResults = result.toolResults
        #expect(toolResults.count == 1)
        if let first = toolResults.first, case .static(let staticResult) = first {
            #expect(staticResult.providerExecuted == true)
            #expect(staticResult.output == .object(["example": .string("example")]))
        }
    }

    // MARK: - Dynamic tools

    @Test("dynamic tools execute on the client")
    func dynamicToolsExecuteOnClient() async throws {
        let toolExecuted = Flag()

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "dynamicTool",
                            input: #"{ "value": "test" }"#
                        )
                    ],
                    finishReason: .toolCalls,
                    usage: testUsage
                )
            )
        )

        let tools: ToolSet = [
            "dynamicTool": dynamicTool(
                inputSchema: toolInputSchema(),
                execute: { _, _ in
                    await toolExecuted.set()
                    return .value(.object(["value": .string("test-result")]))
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input"
        )

        #expect(await toolExecuted.get() == true)

        let content = result.content
        #expect(content.count == 2)
        if content.count == 2 {
            if case .toolCall(let toolCall, _) = content[0] {
                #expect(toolCall.toolCallId == "call-1")
                #expect(toolCall.toolName == "dynamicTool")
                #expect(toolCall.input == JSONValue.object(["value": .string("test")]))
                #expect(toolCall.isDynamic)
            }

            if case .toolResult(let toolResult, _) = content[1] {
                if case .dynamic(let dynamicResult) = toolResult {
                    #expect(dynamicResult.output == .object(["value": .string("test-result")]))
                }
            }
        }

        let toolResults = result.toolResults
        #expect(toolResults.count == 1)
        if let first = toolResults.first, case .dynamic(let dynamicResult) = first {
            #expect(dynamicResult.output == .object(["value": .string("test-result")]))
        }
    }

    // MARK: - Tool execution context

    @Test("tool execution receives experimental context")
    func toolExecutionReceivesContext() async throws {
        let contextRecorder = ValueRecorder<JSONValue?>()

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "contextTool",
                            input: #"{ "value": "test" }"#
                        )
                    ],
                    finishReason: .toolCalls,
                    usage: testUsage
                )
            )
        )

        let tools: ToolSet = [
            "contextTool": tool(
                inputSchema: toolInputSchema(),
                execute: { _, options in
                    await contextRecorder.append(options.experimentalContext)
                    return .value(.object(["value": .string("result")]))
                }
            )
        ]

        let context: JSONValue = .object(["context": .string("test")])

        _ = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input",
            experimentalContext: context
        ) as DefaultGenerateTextResult<JSONValue>

        let recorded = await contextRecorder.entries().last ?? nil
        #expect(recorded == context)
    }

    // MARK: - Tool execution errors

    @Test("tool execution errors add error part to the content")
    func toolExecutionErrorsAddToContent() async throws {
        let scenario = try await runToolExecutionErrorScenario()
        let content = scenario.result.content
        #expect(content.count == 2)

        if content.count == 2 {
            if case .toolCall(let toolCall, _) = content[0] {
                #expect(toolCall.toolCallId == "call-1")
                #expect(toolCall.toolName == "tool1")
                #expect(toolCall.input == JSONValue.object(["value": .string("value")]))
                #expect(toolCall.providerExecuted == nil)
            }

            if case .toolError(let error, _) = content[1] {
                if case .static(let staticError) = error {
                    #expect(staticError.toolCallId == "call-1")
                    #expect(staticError.toolName == "tool1")
                    #expect(staticError.input == JSONValue.object(["value": .string("value")]))
                    #expect(staticError.providerExecuted == nil)
                    if let sampleError = staticError.error as? SampleToolError {
                        #expect(sampleError == .failure)
                    }
                }
            }
        }
    }

    // MARK: - Preliminary tool results

    @Test("preliminary tool results only keep final output in content")
    func preliminaryToolResultsInContent() async throws {
        let scenario = try await runPreliminaryToolScenario()
        let content = scenario.result.content
        #expect(content.count == 2)

        if content.count == 2 {
            if case .toolCall(let toolCall, _) = content[0] {
                #expect(toolCall.toolName == "cityAttractions")
                #expect(toolCall.toolCallId == "call-1")
                #expect(toolCall.input == JSONValue.object(["city": .string("San Francisco")]))
            } else {
                Issue.record("Expected tool call entry as first content item")
            }

            if case .toolResult(let toolResult, _) = content[1] {
                if case .static(let staticResult) = toolResult {
                    #expect(staticResult.toolName == "cityAttractions")
                    #expect(staticResult.preliminary == nil || staticResult.preliminary == false)
                    #expect(staticResult.output == JSONValue.object([
                        "status": .string("success"),
                        "text": .string("The weather in San Francisco is 72°F"),
                        "temperature": .number(72)
                    ]))
                } else {
                    Issue.record("Expected static tool result for final output")
                }
            } else {
                Issue.record("Expected tool result entry as second content item")
            }
        }
    }

    @Test("preliminary tool results replaced in step content")
    func preliminaryToolResultsInSteps() async throws {
        let scenario = try await runPreliminaryToolScenario()
        let steps = scenario.result.steps
        #expect(steps.count == 1)

        if let step = steps.first {
            #expect(step.finishReason == .toolCalls)
            let content = step.content
            #expect(content.count == 2)

            if content.count == 2 {
                if case .toolCall(let call, _) = content[0] {
                    #expect(call.toolName == "cityAttractions")
                } else {
                    Issue.record("Expected tool call in step content")
                }

                if case .toolResult(let result, _) = content[1] {
                    if case .static(let staticResult) = result {
                        #expect(staticResult.preliminary == nil || staticResult.preliminary == false)
                        #expect(staticResult.output == JSONValue.object([
                            "status": .string("success"),
                            "text": .string("The weather in San Francisco is 72°F"),
                            "temperature": .number(72)
                        ]))
                    } else {
                        Issue.record("Expected static tool result in step content")
                    }
                } else {
                    Issue.record("Expected tool result in step content")
                }
            }

            let responseMessages = step.response.messages
            #expect(responseMessages.count == 2)

            if responseMessages.count == 2 {
                if case .assistant(let assistantMessage) = responseMessages[0] {
                    switch assistantMessage.content {
                    case .parts(let parts):
                        #expect(parts.contains { part in
                            if case .toolCall(let call) = part {
                                return call.toolName == "cityAttractions"
                            }
                            return false
                        })
                    case .text:
                        Issue.record("Expected assistant parts in response message")
                    }
                }

                if case .tool(let toolMessage) = responseMessages[1] {
                    let hasResult = toolMessage.content.contains { part in
                        if case .toolResult(let resultPart) = part {
                            if case .json(let json) = resultPart.output, case .object(let object) = json {
                                return object["status"] == .string("success")
                            }
                        }
                        return false
                    }
                    #expect(hasResult)
                } else {
                    Issue.record("Expected tool message with final result")
                }
            }
        }
    }

    @Test("tool execution errors included in response messages")
    func toolExecutionErrorsIncludedInMessages() async throws {
        let scenario = try await runToolExecutionErrorScenario()
        let messages = scenario.result.response.messages
        #expect(messages.count == 2)

        if messages.count == 2 {
            if case .assistant(let assistantMessage) = messages[0], case .parts(let parts) = assistantMessage.content {
                if let first = parts.first, case .toolCall(let part) = first {
                    #expect(part.toolCallId == "call-1")
                    #expect(part.toolName == "tool1")
                }
            }

            if case .tool(let toolMessage) = messages[1] {
                if let first = toolMessage.content.first, case .toolResult(let resultPart) = first {
                    if case .errorText(let value) = resultPart.output {
                        #expect(value == "test error")
                    }
                }
            }
        }
    }

    // MARK: - Invalid tool calls

    @Test("invalid tool calls add error content")
    func invalidToolCallsAddErrorContent() async throws {
        let scenario = try await runInvalidToolCallScenario()
        let content = scenario.result.content
        #expect(content.count == 2)

        if content.count == 2 {
            if case .toolCall(let call, _) = content[0] {
                #expect(call.toolCallId == "call-1")
                #expect(call.toolName == "cityAttractions")
                #expect(call.input == JSONValue.object(["cities": .string("San Francisco")]))
                #expect(call.invalid == true)
            }

            if case .toolError(let error, _) = content[1] {
                if case .dynamic(let dynamicError) = error {
                    #expect(dynamicError.toolCallId == "call-1")
                    #expect(dynamicError.toolName == "cityAttractions")
                    #expect(dynamicError.input == JSONValue.object(["cities": .string("San Francisco")]))
                    let message = String(describing: dynamicError.error)
                    #expect(message.contains("Invalid input for tool cityAttractions"))
                }
            }
        }
    }

    @Test("invalid tool calls reflected in response messages")
    func invalidToolCallsIncludedInMessages() async throws {
        let scenario = try await runInvalidToolCallScenario()
        let messages = scenario.result.response.messages
        #expect(messages.count == 2)

        if messages.count == 2 {
            if case .assistant(let assistantMessage) = messages[0], case .parts(let parts) = assistantMessage.content {
                if let first = parts.first, case .toolCall(let part) = first {
                    #expect(part.toolCallId == "call-1")
                    #expect(part.toolName == "cityAttractions")
                }
            }

            if case .tool(let toolMessage) = messages[1] {
                if let first = toolMessage.content.first, case .toolResult(let resultPart) = first {
                    if case .errorText(let value) = resultPart.output {
                        #expect(value.contains("Invalid input for tool cityAttractions"))
                    }
                }
            }
        }
    }

    // MARK: - Shared utilities

    private func summarizeMessages(_ messages: [ModelMessage]) -> [String] {
        messages.flatMap { message -> [String] in
            switch message {
            case .system(let systemMessage):
                return ["system:text:\(systemMessage.content)"]
            case .user(let userMessage):
                switch userMessage.content {
                case .text(let text):
                    return ["user:text:\(text)"]
                case .parts(let parts):
                    return parts.flatMap { part -> [String] in
                        switch part {
                        case .text(let textPart):
                            return ["user:text:\(textPart.text)"]
                        case .image, .file:
                            return ["user:part"]
                        }
                    }
                }
            case .assistant(let assistantMessage):
                switch assistantMessage.content {
                case .text(let text):
                    return ["assistant:text:\(text)"]
                case .parts(let parts):
                    return parts.map { part -> String in
                        switch part {
                        case .text(let textPart):
                            return "assistant:text:\(textPart.text)"
                        case .file:
                            return "assistant:file"
                        case .reasoning:
                            return "assistant:reasoning"
                        case .toolCall(let toolCallPart):
                            return "assistant:tool-call:\(toolCallPart.toolName)"
                        case .toolResult(let toolResultPart):
                            return "assistant:tool-result:\(toolResultPart.toolName)"
                        case .toolApprovalRequest:
                            return "assistant:tool-approval"
                        }
                    }
                }
            case .tool(let toolMessage):
                return toolMessage.content.map { part in
                    switch part {
                    case .toolResult(let toolResult):
                        return "tool:tool-result:\(toolResult.toolName)"
                    case .toolApprovalResponse:
                        return "tool:approval-response"
                    }
                }
            }
        }
    }

    // MARK: - Helpers

    private func toolInputSchema(requiredKey: String = "value") -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(toolSchemaJSON(requiredKey: requiredKey))
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

    private func customToolSchema(requiredKey: String) -> JSONValue {
        .object([
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

    private func textContent(_ text: String) -> LanguageModelV3Content {
        .text(LanguageModelV3Text(text: text, providerMetadata: nil))
    }

    private func textOutputSpecification() -> Output.Specification<String, JSONValue> {
        Output.Specification<String, JSONValue>(
            type: .text,
            responseFormat: { .text },
            parsePartial: { _ in nil },
            parseOutput: { text, _ in text }
        )
    }

    private func summaryOutputSchema(requiredKey: String = "summary") -> FlexibleSchema<SummaryOutput> {
        let schemaJSON: JSONValue = .object([
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

        return FlexibleSchema(
            Schema<SummaryOutput>(
                jsonSchemaResolver: { schemaJSON }
            ) { value in
                do {
                    let converted: JSONValue
                    if let existing = value as? JSONValue {
                        converted = existing
                    } else {
                        converted = try jsonValue(from: value)
                    }

                    let data = try JSONEncoder().encode(converted)
                    let decoded = try JSONDecoder().decode(SummaryOutput.self, from: data)
                    return .success(value: decoded)
                } catch {
                    let wrapped = TypeValidationError.wrap(value: value, cause: error)
                    return .failure(error: wrapped)
                }
            }
        )
    }

    private func mockId(prefix: String) -> IDGenerator {
        let counter = IDCounter(prefix: prefix)
        return {
            counter.next()
        }
    }

    private func preliminaryStream(city: String) -> AsyncThrowingStream<JSONValue, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(
                JSONValue.object([
                    "status": .string("loading"),
                    "text": .string("Getting weather for \(city)"),
                ])
            )
            continuation.yield(
                JSONValue.object([
                    "status": .string("success"),
                    "text": .string("The weather in \(city) is 72°F"),
                    "temperature": .number(72)
                ])
            )
            continuation.finish()
        }
    }

    private func extractCity(from value: JSONValue) -> String {
        guard case .object(let object) = value,
              case .string(let city) = object["city"] else {
            Issue.record("Expected city string in tool input")
            return ""
        }
        return city
    }

    private func runToolExecutionErrorScenario() async throws -> ToolExecutionErrorScenario {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "tool1",
                            input: #"{ "value": "value" }"#
                        )
                    ],
                    finishReason: .toolCalls,
                    usage: testUsage
                )
            )
        )

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: toolInputSchema(),
                execute: { _, _ in
                    throw SampleToolError.failure
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input"
        )

        return ToolExecutionErrorScenario(result: result)
    }

    private func runPreliminaryToolScenario() async throws -> PreliminaryToolScenario {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "cityAttractions",
                            input: #"{ "city": "San Francisco" }"#
                        )
                    ],
                    finishReason: .toolCalls,
                    usage: LanguageModelUsage(inputTokens: 10, outputTokens: 20, totalTokens: 30),
                    providerMetadata: nil,
                    request: nil,
                    response: LanguageModelV3ResponseInfo(
                        id: "test-id",
                        timestamp: Date(timeIntervalSince1970: 0),
                        modelId: "mock-model-id"
                    ),
                    warnings: []
                )
            )
        )

        let tools: ToolSet = [
            "cityAttractions": tool(
                inputSchema: toolInputSchema(requiredKey: "city"),
                execute: { input, _ in
                    let city = extractCity(from: input)
                    return .stream(preliminaryStream(city: city))
                }
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input",
            internalOptions: GenerateTextInternalOptions(
                generateId: mockId(prefix: "test-id"),
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )

        return PreliminaryToolScenario(result: result)
    }

    private func runProviderExecutedToolsScenario() async throws -> ProviderExecutedToolsScenario {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "web_search",
                            input: #"{ "value": "value" }"#,
                            providerExecuted: true
                        ),
                        makeToolResultContent(
                            toolCallId: "call-1",
                            toolName: "web_search",
                            result: .string(#"{ "value": "result1" }"#),
                            providerExecuted: true
                        ),
                        makeToolCallContent(
                            toolCallId: "call-2",
                            toolName: "web_search",
                            input: #"{ "value": "value" }"#,
                            providerExecuted: true
                        ),
                        LanguageModelV3Content.toolResult(
                            LanguageModelV3ToolResult(
                                toolCallId: "call-2",
                                toolName: "web_search",
                                result: JSONValue.string("ERROR"),
                                isError: true,
                                providerExecuted: true
                            )
                        )
                    ],
                    finishReason: .stop,
                    usage: testUsage
                )
            )
        )

        let providerTool = Tool(
            inputSchema: toolInputSchema(),
            execute: nil,
            outputSchema: toolInputSchema(),
            type: .providerDefined,
            id: "test.web_search",
            name: "web_search",
            args: [:]
        )

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: ["web_search": providerTool],
            prompt: "test-input",
            stopWhen: [stepCountIs(4)]
        )

        return ProviderExecutedToolsScenario(result: result)
    }

    private func runInvalidToolCallScenario() async throws -> InvalidToolCallScenario {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [
                        makeToolCallContent(
                            toolCallId: "call-1",
                            toolName: "cityAttractions",
                            input: #"{ "cities": "San Francisco" }"#
                        )
                    ],
                    finishReason: .toolCalls,
                    usage: testUsage
                )
            )
        )

        let tools: ToolSet = [
            "cityAttractions": tool(
                inputSchema: toolInputSchema(requiredKey: "city")
            )
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "What are the tourist attractions in San Francisco?"
        )

        return InvalidToolCallScenario(result: result)
    }
}

// MARK: - Support Types

private enum ToolTestError: Error, LocalizedError {
    case executionFailed

    var errorDescription: String? {
        "Tool execution failed"
    }
}

private enum SampleToolError: Error, LocalizedError, Equatable {
    case failure

    var errorDescription: String? {
        "test error"
    }
}

private enum ToolCallbackType: String, Sendable {
    case onInputAvailable
    case onInputStart
    case onInputDelta
}

private struct ToolCallbackRecord: Sendable {
    let type: ToolCallbackType
    let toolCallId: String
    let messageSummaries: [String]
    let input: JSONValue?
    let inputTextDelta: String?
}

private struct SummaryOutput: Codable, Equatable, Sendable {
    let summary: String
}

private struct PreliminaryToolScenario: Sendable {
    let result: DefaultGenerateTextResult<JSONValue>
}

private struct ToolExecutionErrorScenario: Sendable {
    let result: DefaultGenerateTextResult<JSONValue>
}

private struct ProviderExecutedToolsScenario: Sendable {
    let result: DefaultGenerateTextResult<JSONValue>
}

private struct InvalidToolCallScenario: Sendable {
    let result: DefaultGenerateTextResult<JSONValue>
}

private final class WarningCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var collected: [[Warning]] = []

    func append(_ warnings: [Warning]) {
        lock.lock()
        collected.append(warnings)
        lock.unlock()
    }

    func entries() -> [[Warning]] {
        lock.lock()
        let snapshot = collected
        lock.unlock()
        return snapshot
    }
}

private actor Flag {
    private var value = false

    func set() {
        value = true
    }

    func get() -> Bool {
        value
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

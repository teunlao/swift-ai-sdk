import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("StreamText – programmatic tool calling")
struct StreamTextProgrammaticToolCallingTests {
    private final class LockedValue<Value>: @unchecked Sendable {
        private var value: Value
        private let lock = NSLock()

        init(initial: Value) {
            self.value = initial
        }

        func withValue<R>(_ body: (inout Value) -> R) -> R {
            lock.lock()
            defer { lock.unlock() }
            return body(&value)
        }
    }

    private let containerId = "container_011CWHPPTDTn1XufeRB9uHeH"
    private let codeExecutionToolCallId = "srvtoolu_01MzSrFWsmzBdcoQkGWLyRjK"

    private var containerProviderMetadata: ProviderMetadata {
        [
            "anthropic": [
                "container": .object([
                    "id": .string(containerId)
                ])
            ]
        ]
    }

    private func codeExecutionTool() -> Tool {
        let inputSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "code": .object(["type": .string("string")]),
                    // Programmatic tool calling inputs include an additional `type` field.
                    // Upstream (Zod) strips unknown keys; this schema accepts the field.
                    "type": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("code")]),
                "additionalProperties": .bool(false),
            ])
        ))

        let outputSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "stdout": .object(["type": .string("string")]),
                    "stderr": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("stdout"), .string("stderr")]),
                "additionalProperties": .bool(true),
            ])
        ))

        let factory = createProviderToolFactoryWithOutputSchema(
            id: "anthropic.code_execution_20250825",
            name: "code_execution",
            inputSchema: inputSchema,
            outputSchema: outputSchema,
            supportsDeferredResults: true
        )

        return factory(ProviderToolFactoryWithOutputSchemaOptions(args: [:]))
    }

    private func rollDieTool(executions: LockedValue<[String]>) -> Tool {
        let inputSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "player": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("player")]),
                "additionalProperties": .bool(false),
            ])
        ))

        return tool(
            description: "Roll a die and return the result.",
            providerOptions: [
                "anthropic": .object([
                    "allowedCallers": .array([.string("code_execution_20250825")]),
                ])
            ],
            inputSchema: inputSchema,
            execute: { input, _ in
                guard case .object(let object) = input,
                      case .string(let player) = object["player"] else {
                    executions.withValue { $0.append("invalid") }
                    return .value(.null)
                }

                executions.withValue { $0.append(player) }
                return .value(player == "player1" ? 6 : 3)
            }
        )
    }

    @Test("5 steps: provider tool triggers client tool across multiple turns (dice game fixture)")
    func diceGameFixture() async throws {
        let usage = LanguageModelV3Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))

        let step1Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-1",
                modelId: "claude-sonnet-4-5-20250929",
                timestamp: Date(timeIntervalSince1970: 0)
            ),
            .textStart(id: "t1", providerMetadata: nil),
            .textDelta(
                id: "t1",
                delta: "I'll help you simulate this game between two players where one is using a loaded die.",
                providerMetadata: nil
            ),
            .textEnd(id: "t1", providerMetadata: nil),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: codeExecutionToolCallId,
                toolName: "code_execution",
                input: #"{"type":"programmatic-tool-call","code":"game_loop()"}"#,
                providerExecuted: true
            )),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "toolu_019jKkXz4jAdwHweHBw92CVY",
                toolName: "rollDie",
                input: #"{ "player": "player1" }"#
            )),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: containerProviderMetadata
            ),
        ]

        let step2Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-2",
                modelId: "claude-sonnet-4-5-20250929",
                timestamp: Date(timeIntervalSince1970: 1)
            ),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "toolu_015dGLMbwBKv1ZRQr6KdJzeH",
                toolName: "rollDie",
                input: #"{ "player": "player2" }"#
            )),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: containerProviderMetadata
            ),
        ]

        let step3Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-3",
                modelId: "claude-sonnet-4-5-20250929",
                timestamp: Date(timeIntervalSince1970: 2)
            ),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "toolu_01PMcE1JBKCeLjn83cgUCvR5",
                toolName: "rollDie",
                input: #"{ "player": "player1" }"#
            )),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "toolu_01MZf5QJ1EQyd2yGyeLzBxAS",
                toolName: "rollDie",
                input: #"{ "player": "player2" }"#
            )),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: containerProviderMetadata
            ),
        ]

        let step4Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-4",
                modelId: "claude-sonnet-4-5-20250929",
                timestamp: Date(timeIntervalSince1970: 3)
            ),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "toolu_01DiUBRds64sNajVPTZRrDSM",
                toolName: "rollDie",
                input: #"{ "player": "player1" }"#
            )),
            .toolCall(LanguageModelV3ToolCall(
                toolCallId: "toolu_01XQa3r3y1Fe8rnkGSncq626",
                toolName: "rollDie",
                input: #"{ "player": "player2" }"#
            )),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: containerProviderMetadata
            ),
        ]

        let codeExecutionResult: JSONValue = .object([
            "type": .string("code_execution_result"),
            "stdout": .string("OK"),
            "stderr": .string(""),
            "return_code": .number(0),
            "content": .array([]),
        ])

        let step5Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(
                id: "msg-5",
                modelId: "claude-sonnet-4-5-20250929",
                timestamp: Date(timeIntervalSince1970: 4)
            ),
            .toolResult(LanguageModelV3ToolResult(
                toolCallId: codeExecutionToolCallId,
                toolName: "code_execution",
                result: codeExecutionResult,
                providerExecuted: true
            )),
            .textStart(id: "t2", providerMetadata: nil),
            .textDelta(id: "t2", delta: "**Game Over!**", providerMetadata: nil),
            .textEnd(id: "t2", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: usage,
                providerMetadata: nil
            ),
        ]

        let model = MockLanguageModelV3(
            provider: "anthropic",
            modelId: "claude-sonnet-4-5-20250929",
            doStream: .array([
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step1Parts)),
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step2Parts)),
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step3Parts)),
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step4Parts)),
                LanguageModelV3StreamResult(stream: makeAsyncStream(from: step5Parts)),
            ])
        )

        let executions = LockedValue(initial: [String]())
        let prepareStepCalls = LockedValue(initial: [Int]())

        let tools: ToolSet = [
            "code_execution": codeExecutionTool(),
            "rollDie": rollDieTool(executions: executions),
        ]

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "Play a dice game between two players.",
            tools: tools,
            prepareStep: { options in
                prepareStepCalls.withValue { $0.append(options.stepNumber) }

                guard options.stepNumber > 0, let lastStep = options.steps.last else {
                    return nil
                }

                guard let container = lastStep.providerMetadata?["anthropic"]?["container"],
                      case .object(let object) = container,
                      case .string(let containerId) = object["id"] else {
                    return nil
                }

                return PrepareStepResult(providerOptions: [
                    "anthropic": [
                        "container": .object([
                            "id": .string(containerId)
                        ])
                    ]
                ])
            },
            stopWhen: [stepCountIs(10)]
        )

        _ = try await convertReadableStreamToArray(result.fullStream)

        #expect(model.doStreamCalls.count == 5)
        #expect(try await result.steps.count == 5)

        let recordedPrepareSteps = prepareStepCalls.withValue { $0 }
        #expect(recordedPrepareSteps == [0, 1, 2, 3, 4])

        // Step 2 should forward the container ID via providerOptions.
        #expect(model.doStreamCalls[0].providerOptions == nil)
        #expect(model.doStreamCalls[1].providerOptions?["anthropic"]?["container"] == .object(["id": .string(containerId)]))

        // Step 2 prompt should include tool results from step 1.
        let step2Prompt = model.doStreamCalls[1].prompt
        #expect(step2Prompt.count == 3)
        if step2Prompt.count == 3, case .tool(let toolParts, _) = step2Prompt[2] {
            guard let firstPart = toolParts.first, case .toolResult(let resultPart) = firstPart else {
                Issue.record("Expected tool-result in step 2 prompt.")
                return
            }

            #expect(resultPart.toolName == "rollDie")
            if case .json(value: let value, providerOptions: _) = resultPart.output {
                #expect(value == 6)
            } else {
                Issue.record("Expected json tool output in step 2 prompt.")
            }
        }

        // rollDie should have been executed for every client tool call.
        let recordedExecutions = executions.withValue { $0 }
        #expect(recordedExecutions.count == 6)
        #expect(recordedExecutions.filter { $0 == "player1" }.count == 3)
        #expect(recordedExecutions.filter { $0 == "player2" }.count == 3)

        // Final content should contain the deferred provider tool result and final text.
        let finalContent = try await result.content
        #expect(finalContent.count == 2)
        if finalContent.count == 2 {
            if case .toolResult(let toolResult, _) = finalContent[0],
               case .static(let staticResult) = toolResult {
                #expect(staticResult.toolCallId == codeExecutionToolCallId)
                #expect(staticResult.toolName == "code_execution")
                #expect(staticResult.providerExecuted == true)
                #expect(staticResult.input == .null)
                #expect(staticResult.output == codeExecutionResult)
            } else {
                Issue.record("Expected provider tool result as first content part.")
            }

            if case .text(let text, _) = finalContent[1] {
                #expect(text == "**Game Over!**")
            } else {
                Issue.record("Expected final text as second content part.")
            }
        }
    }
}

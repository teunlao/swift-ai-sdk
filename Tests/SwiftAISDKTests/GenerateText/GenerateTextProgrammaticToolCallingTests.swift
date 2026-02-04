import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateText – programmatic tool calling")
struct GenerateTextProgrammaticToolCallingTests {
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

    private let containerId = "container_011CWHQB57xVregfCMPrKgew"
    private let codeExecutionToolCallId = "srvtoolu_01CberhXc9TgYXrCZU8bQoks"

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

        let step1 = LanguageModelV3GenerateResult(
            content: [
                .text(.init(text: "I'll help you simulate this dice game between two players!")),
                .toolCall(.init(
                    toolCallId: codeExecutionToolCallId,
                    toolName: "code_execution",
                    input: #"{"type":"programmatic-tool-call","code":"game_loop()"}"#,
                    providerExecuted: true
                )),
                .toolCall(.init(
                    toolCallId: "toolu_01PMcE1JBKCeLjn83cgUCvR5",
                    toolName: "rollDie",
                    input: #"{ "player": "player2" }"#
                )),
                .toolCall(.init(
                    toolCallId: "toolu_01MZf5QJ1EQyd2yGyeLzBxAS",
                    toolName: "rollDie",
                    input: #"{ "player": "player1" }"#
                )),
            ],
            finishReason: .toolCalls,
            usage: usage,
            providerMetadata: containerProviderMetadata
        )

        let step2 = LanguageModelV3GenerateResult(
            content: [
                .toolCall(.init(
                    toolCallId: "toolu_01UvVQ2xwA6preZppeajCkYK",
                    toolName: "rollDie",
                    input: #"{ "player": "player1" }"#
                )),
                .toolCall(.init(
                    toolCallId: "toolu_01BghspNownQFtRgv8jVicr3",
                    toolName: "rollDie",
                    input: #"{ "player": "player2" }"#
                )),
            ],
            finishReason: .toolCalls,
            usage: usage,
            providerMetadata: containerProviderMetadata
        )

        let step3 = LanguageModelV3GenerateResult(
            content: [
                .toolCall(.init(
                    toolCallId: "toolu_01T7Upuuv8C71nq7DZ9ZPNQW",
                    toolName: "rollDie",
                    input: #"{ "player": "player1" }"#
                )),
                .toolCall(.init(
                    toolCallId: "toolu_016Da1tDet9Bf7dAdYTkF5Ar",
                    toolName: "rollDie",
                    input: #"{ "player": "player2" }"#
                )),
            ],
            finishReason: .toolCalls,
            usage: usage,
            providerMetadata: containerProviderMetadata
        )

        let step4 = LanguageModelV3GenerateResult(
            content: [
                .toolCall(.init(
                    toolCallId: "toolu_01DiUBRds64sNajVPTZRrDSM",
                    toolName: "rollDie",
                    input: #"{ "player": "player1" }"#
                )),
                .toolCall(.init(
                    toolCallId: "toolu_01XQa3r3y1Fe8rnkGSncq626",
                    toolName: "rollDie",
                    input: #"{ "player": "player2" }"#
                )),
            ],
            finishReason: .toolCalls,
            usage: usage,
            providerMetadata: containerProviderMetadata
        )

        let codeExecutionResult: JSONValue = .object([
            "type": .string("code_execution_result"),
            "stdout": .string("OK"),
            "stderr": .string(""),
            "return_code": .number(0),
            "content": .array([]),
        ])

        let step5 = LanguageModelV3GenerateResult(
            content: [
                .toolResult(.init(
                    toolCallId: codeExecutionToolCallId,
                    toolName: "code_execution",
                    result: codeExecutionResult
                )),
                .text(.init(text: "**Game Over!**")),
            ],
            finishReason: .stop,
            usage: usage
        )

        let model = MockLanguageModelV3(
            provider: "anthropic",
            modelId: "claude-sonnet-4-5-20250929",
            doGenerate: .array([step1, step2, step3, step4, step5])
        )

        let executions = LockedValue(initial: [String]())
        let prepareStepCalls = LockedValue(initial: [Int]())

        let tools: ToolSet = [
            "code_execution": codeExecutionTool(),
            "rollDie": rollDieTool(executions: executions),
        ]

        let result: DefaultGenerateTextResult<JSONValue> = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "Play a dice game between two players.",
            stopWhen: [stepCountIs(10)],
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
            }
        )

        #expect(result.steps.count == 5)
        #expect(model.doGenerateCalls.count == 5)

        let recordedPrepareSteps = prepareStepCalls.withValue { $0 }
        #expect(recordedPrepareSteps == [0, 1, 2, 3, 4])

        // Step 2 should forward the container ID via providerOptions.
        #expect(model.doGenerateCalls[0].providerOptions == nil)
        #expect(model.doGenerateCalls[1].providerOptions?["anthropic"]?["container"] == .object(["id": .string(containerId)]))

        // Step 2 prompt should include tool results from step 1.
        let step2Prompt = model.doGenerateCalls[1].prompt
        #expect(step2Prompt.count == 3)
        if step2Prompt.count == 3, case .tool(let toolParts, _) = step2Prompt[2] {
            var resultsById: [String: JSONValue] = [:]
            for part in toolParts {
                guard case .toolResult(let resultPart) = part else { continue }
                if case .json(value: let value, providerOptions: _) = resultPart.output {
                    resultsById[resultPart.toolCallId] = value
                }
            }

            #expect(resultsById["toolu_01PMcE1JBKCeLjn83cgUCvR5"] == 3)
            #expect(resultsById["toolu_01MZf5QJ1EQyd2yGyeLzBxAS"] == 6)
        } else {
            Issue.record("Expected tool results in step 2 prompt.")
        }

        // Final step prompt should include all prior response messages.
        #expect(model.doGenerateCalls[4].prompt.count == 9)

        // rollDie should have been executed for every client tool call.
        let recordedExecutions = executions.withValue { $0 }
        #expect(recordedExecutions.count == 8)
        #expect(recordedExecutions.filter { $0 == "player1" }.count == 4)
        #expect(recordedExecutions.filter { $0 == "player2" }.count == 4)

        // Final content should contain the deferred provider tool result and final text.
        #expect(result.content.count == 2)
        if result.content.count == 2 {
            if case .toolResult(let toolResult, _) = result.content[0],
               case .static(let staticResult) = toolResult {
                #expect(staticResult.toolCallId == codeExecutionToolCallId)
                #expect(staticResult.toolName == "code_execution")
                #expect(staticResult.providerExecuted == true)
                #expect(staticResult.input == .null)
                #expect(staticResult.output == codeExecutionResult)
            } else {
                Issue.record("Expected provider tool result as first content part.")
            }

            if case .text(let text, _) = result.content[1] {
                #expect(text == "**Game Over!**")
            } else {
                Issue.record("Expected final text as second content part.")
            }
        }

        // Response messages should contain all assistant/tool messages from all steps.
        #expect(result.response.messages.count == 9)
    }
}

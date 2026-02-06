import Foundation
import AISDKProvider
import AISDKProviderUtils
import SwiftAISDK
import Testing

@Suite("GenerateText – timeout")
struct GenerateTextTimeoutTests {
    private func makeSchema() -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("value")]),
                    "additionalProperties": .bool(false),
                ])
            )
        )
    }

    @Test("timeout forwards abort signal to model")
    func timeoutForwardsAbortSignalToModel() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [],
                    finishReason: .stop,
                    usage: LanguageModelV3Usage()
                )
            )
        )

        _ = try await generateText(
            model: .v3(model),
            prompt: "test-input",
            settings: CallSettings(timeout: 5000)
        ) as DefaultGenerateTextResult<JSONValue>

        #expect(model.doGenerateCalls.count == 1)
        #expect(model.doGenerateCalls.first?.abortSignal != nil)
    }

    @Test("no timeout and no abortSignal passes nil to model")
    func noTimeoutPassesNilAbortSignalToModel() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [],
                    finishReason: .stop,
                    usage: LanguageModelV3Usage()
                )
            )
        )

        _ = try await generateText(
            model: .v3(model),
            prompt: "test-input"
        ) as DefaultGenerateTextResult<JSONValue>

        #expect(model.doGenerateCalls.count == 1)
        #expect(model.doGenerateCalls.first?.abortSignal == nil)
    }

    @Test("timeout object without totalMs/stepMs does not create abort signal")
    func emptyTimeoutObjectDoesNotCreateAbortSignal() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
                    content: [],
                    finishReason: .stop,
                    usage: LanguageModelV3Usage()
                )
            )
        )

        _ = try await generateText(
            model: .v3(model),
            prompt: "test-input",
            settings: CallSettings(timeout: .configuration())
        ) as DefaultGenerateTextResult<JSONValue>

        #expect(model.doGenerateCalls.count == 1)
        #expect(model.doGenerateCalls.first?.abortSignal == nil)
    }

    @Test("timeout forwards abort signal to tool execution")
    func timeoutForwardsAbortSignalToToolExecution() async throws {
        final class LockedValue<Value>: @unchecked Sendable {
            private var value: Value
            private let lock = NSLock()

            init(_ initial: Value) { value = initial }

            func set(_ newValue: Value) {
                lock.lock()
                value = newValue
                lock.unlock()
            }

            func get() -> Value {
                lock.lock()
                let v = value
                lock.unlock()
                return v
            }
        }

        let capturedAbortSignal = LockedValue<(@Sendable () -> Bool)?>(nil)
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(
                LanguageModelV3GenerateResult(
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
                    usage: LanguageModelV3Usage()
                )
            )
        )

        let tools: ToolSet = [
            "tool1": tool(
                inputSchema: makeSchema(),
                execute: { _, options in
                    capturedAbortSignal.set(options.abortSignal)
                    return .value(.string("ok"))
                }
            )
        ]

        _ = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test-input",
            settings: CallSettings(timeout: 5000)
        ) as DefaultGenerateTextResult<JSONValue>

        #expect(capturedAbortSignal.get() != nil)
    }
}

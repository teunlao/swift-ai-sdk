import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

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

@Suite("PrepareStep – providerOptions and contexts")
struct PrepareStepProviderOptionsTests {
    @Test("prepareStep merges providerOptions for its step and replaces the contexts for later steps")
    func prepareStepOverridesProviderOptionsAndContexts() async throws {
        let baseProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("base"),
                    "keep": .string("x"),
                ]),
            ],
            "base": [
                "a": .string("1"),
            ],
        ]

        let step0ProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("override"),
                ]),
            ],
            "extra": [
                "b": .string("2"),
            ],
        ]

        let expectedStep0ProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("override"),
                    "keep": .string("x"),
                ]),
            ],
            "base": [
                "a": .string("1"),
            ],
            "extra": [
                "b": .string("2"),
            ],
        ]

        let initialContext: Context = ["ctx": .string("initial")]
        let step0Context: Context = ["ctx": .string("step0")]
        let step0ToolContext: Context = ["key": .string("step0")]

        let runtimeContexts = LockedValue(initial: [Context]())

        let tools: ToolSet = [
            "tool1": Tool(
                description: "Test tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .never,
                execute: { _, options in
                    #expect(options.context == step0ToolContext)
                    return .value(.string("ok"))
                }
            )
        ]

        let usage = LanguageModelV4Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))
        let model = MockLanguageModelV4(
            doGenerate: .array([
                LanguageModelV4GenerateResult(
                    content: [
                        .toolCall(LanguageModelV4ToolCall(
                            toolCallId: "call-1",
                            toolName: "tool1",
                            input: #"{}"#
                        ))
                    ],
                    finishReason: .toolCalls,
                    usage: usage
                ),
                LanguageModelV4GenerateResult(
                    content: [
                        .text(LanguageModelV4Text(text: "done"))
                    ],
                    finishReason: .stop,
                    usage: usage
                ),
            ])
        )

        _ = try await generateText(
            model: model,
            tools: tools,
            prompt: "test",
            stopWhen: [isStepCount(2)],
            providerOptions: baseProviderOptions,
            prepareStep: { options in
                runtimeContexts.withValue { $0.append(options.runtimeContext) }
                guard options.stepNumber == 0 else { return nil }
                return PrepareStepResult(
                    toolsContext: ["tool1": step0ToolContext],
                    runtimeContext: step0Context,
                    providerOptions: step0ProviderOptions
                )
            },
            runtimeContext: initialContext
        )

        #expect(model.doGenerateCalls.count == 2)
        #expect(model.doGenerateCalls[0].providerOptions == expectedStep0ProviderOptions)
        #expect(model.doGenerateCalls[1].providerOptions == baseProviderOptions)
        #expect(runtimeContexts.withValue { $0 } == [initialContext, step0Context])
    }
}

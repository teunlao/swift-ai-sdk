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

@Suite("PrepareStep – providerOptions + experimentalContext")
struct PrepareStepProviderOptionsTests {
    @Test("prepareStep can override providerOptions and experimentalContext")
    func prepareStepOverridesProviderOptionsAndExperimentalContext() async throws {
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

        let initialContext: JSONValue = .object(["ctx": .string("initial")])
        let step0Context: JSONValue = .object(["ctx": .string("step0")])

        let prepareSnapshots = LockedValue(initial: [(step: Int, context: JSONValue?)]())

        let tools: ToolSet = [
            "tool1": Tool(
                description: "Test tool",
                inputSchema: FlexibleSchema(jsonSchema(.object([:]))),
                needsApproval: .never,
                execute: { _, options in
                    #expect(options.experimentalContext == step0Context)
                    return .value(.string("ok"))
                }
            )
        ]

        let usage = LanguageModelV3Usage(inputTokens: .init(total: 1), outputTokens: .init(total: 1))
        let model = MockLanguageModelV3(
            doGenerate: .array([
                LanguageModelV3GenerateResult(
                    content: [
                        .toolCall(LanguageModelV3ToolCall(
                            toolCallId: "call-1",
                            toolName: "tool1",
                            input: #"{}"#
                        ))
                    ],
                    finishReason: .toolCalls,
                    usage: usage
                ),
                LanguageModelV3GenerateResult(
                    content: [
                        .text(LanguageModelV3Text(text: "done"))
                    ],
                    finishReason: .stop,
                    usage: usage
                ),
            ])
        )

        _ = try await generateText(
            model: .v3(model),
            tools: tools,
            prompt: "test",
            stopWhen: [stepCountIs(2)],
            providerOptions: baseProviderOptions,
            prepareStep: { options in
                prepareSnapshots.withValue { $0.append((step: options.stepNumber, context: options.experimentalContext)) }

                if options.stepNumber == 0 {
                    #expect(options.experimentalContext == initialContext)
                    return PrepareStepResult(
                        experimentalContext: step0Context,
                        providerOptions: step0ProviderOptions
                    )
                }

                if options.stepNumber == 1 {
                    #expect(options.experimentalContext == step0Context)
                }

                return nil
            },
            experimentalContext: initialContext
        ) as DefaultGenerateTextResult<JSONValue>

        #expect(model.doGenerateCalls.count == 2)
        #expect(model.doGenerateCalls[0].providerOptions == expectedStep0ProviderOptions)
        #expect(model.doGenerateCalls[1].providerOptions == baseProviderOptions)

        let snapshots = prepareSnapshots.withValue { $0 }
        #expect(snapshots.map(\.step) == [0, 1])
    }
}

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

@Suite("streamText – prepareStep parity")
struct StreamTextPrepareStepParityTests {
    @Test("prepareStep applies providerOptions per step and forwards experimentalContext")
    func prepareStepProviderOptionsAndContextParity() async throws {
        let baseProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("base"),
                    "keep": .string("x"),
                ]),
            ],
        ]

        let step0ProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("step0"),
                ]),
            ],
        ]

        let step1ProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("step1"),
                ]),
            ],
        ]

        let expectedStep0ProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("step0"),
                    "keep": .string("x"),
                ]),
            ],
        ]

        let expectedStep1ProviderOptions: ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("step1"),
                    "keep": .string("x"),
                ]),
            ],
        ]

        let initialContext: Context = ["ctx": .string("initial")]
        let step0Context: Context = ["ctx": .string("step0")]
        let step0ToolContext: Context = ["key": .string("step0")]

        let prepareSnapshots = LockedValue(initial: [(step: Int, context: Context)]())

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

        let step0Parts: [LanguageModelV4StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV4ToolCall(
                toolCallId: "call-1",
                toolName: "tool1",
                input: #"{}"#
            )),
            .finish(
                finishReason: .toolCalls,
                usage: usage,
                providerMetadata: nil
            )
        ]

        let step1Parts: [LanguageModelV4StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-1", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 1)),
            .textStart(id: "t", providerMetadata: nil),
            .textDelta(id: "t", delta: "done", providerMetadata: nil),
            .textEnd(id: "t", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: usage,
                providerMetadata: nil
            )
        ]

        let step0Stream = makeAsyncStream(from: step0Parts)
        let step1Stream = makeAsyncStream(from: step1Parts)

        let model = MockLanguageModelV4(
            doStream: .array([
                LanguageModelV4StreamResult(stream: step0Stream),
                LanguageModelV4StreamResult(stream: step1Stream),
            ])
        )

        let result = try streamText(
            model: model,
            tools: tools,
            prompt: "test",
            stopWhen: [isStepCount(3)],
            providerOptions: baseProviderOptions,
            prepareStep: { options in
                prepareSnapshots.withValue { $0.append((step: options.stepNumber, context: options.runtimeContext)) }

                if options.stepNumber == 0 {
                    return PrepareStepResult(
                        toolsContext: ["tool1": step0ToolContext],
                        runtimeContext: step0Context,
                        providerOptions: step0ProviderOptions
                    )
                }

                if options.stepNumber == 1 {
                    return PrepareStepResult(providerOptions: step1ProviderOptions)
                }

                return nil
            },
            runtimeContext: initialContext
        )

        _ = try await convertReadableStreamToArray(result.fullStream)

        #expect(model.doStreamCalls.count == 2)
        #expect(model.doStreamCalls[0].providerOptions == expectedStep0ProviderOptions)
        #expect(model.doStreamCalls[1].providerOptions == expectedStep1ProviderOptions)

        let snapshots = prepareSnapshots.withValue { $0 }
        #expect(snapshots.map(\.step) == [0, 1])
        #expect(snapshots.map(\.context) == [initialContext, step0Context])
    }
}

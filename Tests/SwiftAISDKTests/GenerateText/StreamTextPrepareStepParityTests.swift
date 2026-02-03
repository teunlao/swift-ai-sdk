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

        let usage = LanguageModelV3Usage(inputTokens: 1, outputTokens: 1, totalTokens: 2)

        let step0Parts: [LanguageModelV3StreamPart] = [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .toolCall(LanguageModelV3ToolCall(
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

        let step1Parts: [LanguageModelV3StreamPart] = [
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

        let model = MockLanguageModelV3(
            doStream: .array([
                LanguageModelV3StreamResult(stream: step0Stream),
                LanguageModelV3StreamResult(stream: step1Stream),
            ])
        )

        let result: DefaultStreamTextResult<JSONValue, JSONValue> = try streamText(
            model: .v3(model),
            prompt: "test",
            tools: tools,
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
                    return PrepareStepResult(providerOptions: step1ProviderOptions)
                }

                return nil
            },
            experimentalContext: initialContext,
            stopWhen: [stepCountIs(3)]
        )

        _ = try await convertReadableStreamToArray(result.fullStream)

        #expect(model.doStreamCalls.count == 2)
        #expect(model.doStreamCalls[0].providerOptions == expectedStep0ProviderOptions)
        #expect(model.doStreamCalls[1].providerOptions == expectedStep1ProviderOptions)

        let snapshots = prepareSnapshots.withValue { $0 }
        #expect(snapshots.map(\.step) == [0, 1])
    }
}


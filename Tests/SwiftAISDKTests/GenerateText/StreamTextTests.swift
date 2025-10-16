/**
 StreamText Tests

 Port of `@ai-sdk/ai/src/generate-text/stream-text.test.ts`.
 */

import Testing
import Foundation
@testable import SwiftAISDK
@testable import AISDKProvider

// MARK: - Test Helpers

private let testUsage = LanguageModelUsage(
    inputTokens: 3,
    outputTokens: 10,
    totalTokens: 13
)

private func createTestModel(
    stream: [LanguageModelV3StreamPart]? = nil
) -> MockLanguageModelV3 {
    let defaultStream: [LanguageModelV3StreamPart] = [
        .streamStart(warnings: []),
        .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
        .textStart(id: "1", providerMetadata: nil),
        .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
        .textDelta(id: "1", delta: ", ", providerMetadata: nil),
        .textDelta(id: "1", delta: "world!", providerMetadata: nil),
        .textEnd(id: "1", providerMetadata: nil),
        .finish(
            finishReason: .stop,
            usage: testUsage,
            providerMetadata: ["testProvider": ["testKey": "testValue"]]
        )
    ]

    return MockLanguageModelV3(
        doStream: .function { _ in
            let parts = stream ?? defaultStream
            return LanguageModelV3StreamResult(
                stream: AsyncThrowingStream { continuation in
                    for part in parts {
                        continuation.yield(part)
                    }
                    continuation.finish()
                },
                request: nil,
                response: nil
            )
        }
    )
}

// MARK: - textStream Tests

@Suite("StreamText - textStream")
struct StreamTextTextStreamTests {

    @Test("should send text deltas")
    func sendsTextDeltas() async throws {
        let model = MockLanguageModelV3(
            doStream: .function { options in
                // Verify prompt
                #expect(options.prompt.count == 1)
                if case .user(let content, _) = options.prompt[0] {
                    #expect(content.count == 1)
                    if case .text(let textPart) = content[0] {
                        #expect(textPart.text == "test-input")
                    } else {
                        Issue.record("Expected text content")
                    }
                } else {
                    Issue.record("Expected user message")
                }

                let parts: [LanguageModelV3StreamPart] = [
                    .textStart(id: "1", providerMetadata: nil),
                    .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
                    .textDelta(id: "1", delta: ", ", providerMetadata: nil),
                    .textDelta(id: "1", delta: "world!", providerMetadata: nil),
                    .textEnd(id: "1", providerMetadata: nil),
                    .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
                ]

                return LanguageModelV3StreamResult(
                    stream: AsyncThrowingStream { continuation in
                        for part in parts {
                            continuation.yield(part)
                        }
                        continuation.finish()
                    },
                    request: nil,
                    response: nil
                )
            }
        )

        let result: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model),
            prompt: "test-input"
        )

        var collected: [String] = []
        for try await chunk in result.textStream {
            collected.append(chunk)
        }

        #expect(collected == ["Hello", ", ", "world!"])
    }

    @Test("should filter out empty text deltas")
    func filtersEmptyTextDeltas() async throws {
        let model = createTestModel(
            stream: [
                .textStart(id: "1", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textDelta(id: "1", delta: "Hello", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textDelta(id: "1", delta: ", ", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textDelta(id: "1", delta: "world!", providerMetadata: nil),
                .textDelta(id: "1", delta: "", providerMetadata: nil),
                .textEnd(id: "1", providerMetadata: nil),
                .finish(finishReason: .stop, usage: testUsage, providerMetadata: nil)
            ]
        )

        let result: DefaultStreamTextResult<Never, Never> = try streamText(
            model: .v3(model),
            prompt: "test-input"
        )

        var collected: [String] = []
        for try await chunk in result.textStream {
            collected.append(chunk)
        }

        #expect(collected == ["Hello", ", ", "world!"])
    }
}

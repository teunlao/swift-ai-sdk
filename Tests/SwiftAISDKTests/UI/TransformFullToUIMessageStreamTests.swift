import Foundation
import Testing
@testable import SwiftAISDK

@Suite("transformFullToUIMessageStream")
struct TransformFullToUIMessageStreamTests {
    @Test("includes reasoning events when enabled")
    func includesReasoningWhenEnabled() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .startStep(
                request: LanguageModelRequestMetadata(body: nil),
                warnings: []
            ),
            .textStart(id: "t1", providerMetadata: nil),
            .textDelta(id: "t1", text: "Hello ", providerMetadata: nil),
            .reasoningStart(id: "r1", providerMetadata: nil),
            .reasoningDelta(id: "r1", text: "think", providerMetadata: nil),
            .reasoningEnd(id: "r1", providerMetadata: nil),
            .textDelta(id: "t1", text: "world", providerMetadata: nil),
            .textEnd(id: "t1", providerMetadata: nil),
            .finishStep(
                response: LanguageModelResponseMetadata(
                    id: "resp-1",
                    timestamp: Date(),
                    modelId: "test",
                    headers: nil
                ),
                usage: LanguageModelUsage(),
                finishReason: .stop,
                providerMetadata: nil
            ),
            .finish(finishReason: .stop, totalUsage: LanguageModelUsage())
        ]

        let fullStream = makeAsyncStream(from: parts)
        let chunkStream = transformFullToUIMessageStream(
            stream: fullStream,
            options: UIMessageTransformOptions(
                sendStart: true,
                sendFinish: true,
                sendReasoning: true,
                sendSources: false,
                messageMetadata: nil
            )
        )

        let chunks = try await collectStream(chunkStream)

        // Verify that reasoning events are present in the expected order
        let types = chunks.map { $0.typeIdentifier }
        #expect(types.contains("start"))
        #expect(types.contains("start-step"))
        #expect(types.contains("text-start"))
        #expect(types.contains("text-delta"))
        #expect(types.contains("reasoning-start"))
        #expect(types.contains("reasoning-delta"))
        #expect(types.contains("reasoning-end"))
        #expect(types.contains("text-end"))
        #expect(types.contains("finish-step"))
        #expect(types.last == "finish")
    }
}

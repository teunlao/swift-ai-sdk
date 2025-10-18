import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider

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

    @Test("includes source url/document when enabled")
    func includesSourcesWhenEnabled() async throws {
        let urlSource = LanguageModelV3Source.url(
            id: "s1",
            url: "https://example.com",
            title: "Example",
            providerMetadata: nil
        )

        let docSource = LanguageModelV3Source.document(
            id: "s2",
            mediaType: "text/plain",
            title: "Readme",
            filename: "README.txt",
            providerMetadata: nil
        )

        let parts: [TextStreamPart] = [
            .start,
            .startStep(
                request: LanguageModelRequestMetadata(body: nil),
                warnings: []
            ),
            .source(urlSource),
            .source(docSource),
            .finishStep(
                response: LanguageModelResponseMetadata(
                    id: "resp-2",
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
                sendReasoning: false,
                sendSources: true,
                messageMetadata: nil
            )
        )

        let chunks = try await collectStream(chunkStream)

        // Validate URL source chunk
        let hasUrl = chunks.contains { chunk in
            if case let .sourceUrl(sourceId, url, title, _) = chunk {
                return sourceId == "s1" && url == "https://example.com" && title == "Example"
            }
            return false
        }
        #expect(hasUrl)

        // Validate Document source chunk
        let hasDoc = chunks.contains { chunk in
            if case let .sourceDocument(sourceId, mediaType, title, filename, _) = chunk {
                return sourceId == "s2" && mediaType == "text/plain" && title == "Readme" && filename == "README.txt"
            }
            return false
        }
        #expect(hasDoc)
    }

    @Test("excludes sources when disabled")
    func excludesSourcesWhenDisabled() async throws {
        let urlSource = LanguageModelV3Source.url(
            id: "s3",
            url: "https://disabled.example",
            title: nil,
            providerMetadata: nil
        )

        let parts: [TextStreamPart] = [
            .start,
            .startStep(
                request: LanguageModelRequestMetadata(body: nil),
                warnings: []
            ),
            .source(urlSource),
            .finishStep(
                response: LanguageModelResponseMetadata(
                    id: "resp-3",
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
                sendReasoning: false,
                sendSources: false,
                messageMetadata: nil
            )
        )

        let chunks = try await collectStream(chunkStream)
        let hasAnySource = chunks.contains { chunk in
            switch chunk {
            case .sourceUrl, .sourceDocument: return true
            default: return false
            }
        }
        #expect(!hasAnySource)
    }

    @Test("excludes reasoning when disabled")
    func excludesReasoningWhenDisabled() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .startStep(
                request: LanguageModelRequestMetadata(body: nil),
                warnings: []
            ),
            .reasoningStart(id: "r1", providerMetadata: nil),
            .reasoningDelta(id: "r1", text: "hidden", providerMetadata: nil),
            .reasoningEnd(id: "r1", providerMetadata: nil),
            .finishStep(
                response: LanguageModelResponseMetadata(
                    id: "resp-4",
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
                sendReasoning: false,
                sendSources: false,
                messageMetadata: nil
            )
        )

        let chunks = try await collectStream(chunkStream)
        let hasAnyReasoning = chunks.contains { chunk in
            switch chunk {
            case .reasoningStart, .reasoningDelta, .reasoningEnd: return true
            default: return false
            }
        }
        #expect(!hasAnyReasoning)
    }

    @Test("does not emit start when sendStart=false")
    func excludesStartWhenDisabled() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .startStep(
                request: LanguageModelRequestMetadata(body: nil),
                warnings: []
            ),
            .textStart(id: "t1", providerMetadata: nil),
            .textDelta(id: "t1", text: "Hi", providerMetadata: nil),
            .textEnd(id: "t1", providerMetadata: nil),
            .finishStep(
                response: LanguageModelResponseMetadata(
                    id: "resp-5",
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
                sendStart: false,
                sendFinish: true,
                sendReasoning: false,
                sendSources: false,
                messageMetadata: nil
            )
        )

        let chunks = try await collectStream(chunkStream)
        let types = chunks.map { $0.typeIdentifier }
        #expect(!types.contains("start"))
        #expect(types.first == "start-step")
    }

    @Test("does not emit finish when sendFinish=false")
    func excludesFinishWhenDisabled() async throws {
        let parts: [TextStreamPart] = [
            .start,
            .startStep(
                request: LanguageModelRequestMetadata(body: nil),
                warnings: []
            ),
            .textStart(id: "t2", providerMetadata: nil),
            .textDelta(id: "t2", text: "Bye", providerMetadata: nil),
            .textEnd(id: "t2", providerMetadata: nil),
            .finishStep(
                response: LanguageModelResponseMetadata(
                    id: "resp-6",
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
                sendFinish: false,
                sendReasoning: false,
                sendSources: false,
                messageMetadata: nil
            )
        )

        let chunks = try await collectStream(chunkStream)
        let types = chunks.map { $0.typeIdentifier }
        #expect(!types.contains("finish"))
        #expect(types.last == "finish-step")
    }
}

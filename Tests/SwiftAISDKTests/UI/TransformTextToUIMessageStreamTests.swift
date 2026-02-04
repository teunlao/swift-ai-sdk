import Foundation
import Testing
@testable import SwiftAISDK

@Suite("transformTextToUIMessageStream")
struct TransformTextToUIMessageStreamTests {
    @Test("transforms text parts into UI message chunks")
    func transformsBasicSequence() async throws {
        let textStream = makeAsyncStream(from: ["Hello", " ", "World"])

        let chunkStream = transformTextToUIMessageStream(stream: textStream)
        let chunks = try await collectStream(chunkStream)

        let expected: [AnyUIMessageChunk] = [
            .start(messageId: nil, messageMetadata: nil),
            .startStep,
            .textStart(id: "text-1", providerMetadata: nil),
            .textDelta(id: "text-1", delta: "Hello", providerMetadata: nil),
            .textDelta(id: "text-1", delta: " ", providerMetadata: nil),
            .textDelta(id: "text-1", delta: "World", providerMetadata: nil),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        #expect(chunks == expected)
    }

    @Test("produces framing chunks for empty streams")
    func handlesEmptyStream() async throws {
        let textStream = makeAsyncStream(from: [String]())

        let chunkStream = transformTextToUIMessageStream(stream: textStream)
        let chunks = try await collectStream(chunkStream)

        let expected: [AnyUIMessageChunk] = [
            .start(messageId: nil, messageMetadata: nil),
            .startStep,
            .textStart(id: "text-1", providerMetadata: nil),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        #expect(chunks == expected)
    }

    @Test("handles single chunk streams")
    func handlesSingleChunk() async throws {
        let textStream = makeAsyncStream(from: ["Complete message"])

        let chunkStream = transformTextToUIMessageStream(stream: textStream)
        let chunks = try await collectStream(chunkStream)

        let expected: [AnyUIMessageChunk] = [
            .start(messageId: nil, messageMetadata: nil),
            .startStep,
            .textStart(id: "text-1", providerMetadata: nil),
            .textDelta(id: "text-1", delta: "Complete message", providerMetadata: nil),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(finishReason: nil, messageMetadata: nil)
        ]

        #expect(chunks == expected)
    }
}

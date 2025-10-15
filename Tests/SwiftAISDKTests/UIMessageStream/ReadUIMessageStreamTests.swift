import Foundation
import Testing
@testable import SwiftAISDK

@Suite("readUIMessageStream")
struct ReadUIMessageStreamTests {
    @Test("should return UI messages for basic stream")
    func readsMessageStream() async throws {
        let stream = makeChunkStream([
            .start(messageId: "msg-123", messageMetadata: nil),
            .startStep,
            .textStart(id: "text-1", providerMetadata: nil),
            .textDelta(id: "text-1", delta: "Hello, ", providerMetadata: nil),
            .textDelta(id: "text-1", delta: "world!", providerMetadata: nil),
            .textEnd(id: "text-1", providerMetadata: nil),
            .finishStep,
            .finish(messageMetadata: nil)
        ])

        let sequence = readUIMessageStream(stream: stream)
        let messages = try await collectAsyncSequence(sequence)

        #expect(messages.count == 5)
        #expect(messages[0] == UIMessage(
            id: "msg-123",
            role: .assistant,
            metadata: nil,
            parts: []
        ))
        #expect(messages[1].parts == [
            .stepStart,
            .text(TextUIPart(text: "", state: .streaming))
        ])
        #expect(messages[2].parts == [
            .stepStart,
            .text(TextUIPart(text: "Hello, ", state: .streaming))
        ])
        #expect(messages[3].parts == [
            .stepStart,
            .text(TextUIPart(text: "Hello, world!", state: .streaming))
        ])
        #expect(messages[4].parts == [
            .stepStart,
            .text(TextUIPart(text: "Hello, world!", state: .done))
        ])
    }

    @Test("should throw when encountering error chunk with terminateOnError")
    func throwsOnError() async {
        let stream = makeChunkStream([
            .start(messageId: "msg-123", messageMetadata: nil),
            .textStart(id: "text-1", providerMetadata: nil),
            .textDelta(id: "text-1", delta: "Hello", providerMetadata: nil),
            .error(errorText: "Test error message")
        ])

        let sequence = readUIMessageStream(
            stream: stream,
            terminateOnError: true
        )

        do {
            _ = try await collectAsyncSequence(sequence)
            Issue.record("Expected readUIMessageStream to throw")
        } catch {
            #expect(String(describing: error) == "Test error message")
        }
    }
}

// MARK: - Helpers

private func makeChunkStream(
    _ chunks: [AnyUIMessageChunk]
) -> AsyncThrowingStream<AnyUIMessageChunk, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

private func collectAsyncSequence<S: AsyncSequence>(
    _ sequence: S
) async throws -> [S.Element] {
    var iterator = sequence.makeAsyncIterator()
    var values: [S.Element] = []
    while let value = try await iterator.next() {
        values.append(value)
    }
    return values
}

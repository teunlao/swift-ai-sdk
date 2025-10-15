import Foundation
import Testing
@testable import SwiftAISDK

@Suite("pipeUIMessageStreamToResponse")
struct PipeUIMessageStreamToResponseTests {
    @Test("should write to response with headers and encoded stream")
    func writesToResponse() async throws {
        let response = MockStreamTextResponseWriter()
        let stream = makeChunkStream([
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "test-data", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil)
        ])

        pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(
                    headers: ["Custom-Header": "test"],
                    status: 200,
                    statusText: "OK"
                )
            )
        )

        await response.waitForEnd()

        #expect(response.statusCode == 200)
        #expect(response.statusMessage == "OK")
        #expect(response.headers.lowercasedKeys() == [
            "content-type": "text/event-stream",
            "cache-control": "no-cache",
            "connection": "keep-alive",
            "x-vercel-ai-ui-message-stream": "v1",
            "x-accel-buffering": "no",
            "custom-header": "test"
        ])

        #expect(response.decodedChunks() == [
            "data: {\"id\":\"1\",\"type\":\"text-start\"}\n\n",
            "data: {\"delta\":\"test-data\",\"id\":\"1\",\"type\":\"text-delta\"}\n\n",
            "data: {\"id\":\"1\",\"type\":\"text-end\"}\n\n",
            "data: [DONE]\n\n"
        ])
    }

    @Test("should handle errors in the stream")
    func writesErrorChunks() async throws {
        let response = MockStreamTextResponseWriter()
        let stream = makeChunkStream([
            .error(errorText: "Custom error message")
        ])

        pipeUIMessageStreamToResponse(
            response: response,
            stream: stream,
            options: StreamTextUIResponseOptions<UIMessage>(
                responseInit: UIMessageStreamResponseInit(status: 200)
            )
        )

        await response.waitForEnd()

        #expect(response.decodedChunks() == [
            "data: {\"errorText\":\"Custom error message\",\"type\":\"error\"}\n\n",
            "data: [DONE]\n\n"
        ])
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

private extension Dictionary where Key == String, Value == String {
    func lowercasedKeys() -> [String: String] {
        reduce(into: [:]) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
    }
}

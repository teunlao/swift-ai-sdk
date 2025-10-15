import Testing
@testable import SwiftAISDK

/**
 Tests for `pipeTextStreamToResponse`.

 Port of `@ai-sdk/ai/src/text-stream/pipe-text-stream-to-response.test.ts`.
 */
@Suite("PipeTextStreamToResponse Tests")
struct PipeTextStreamToResponseTests {

    @Test("should write to response with correct headers and encoded stream")
    func testPipeToResponse() async throws {
        let mockResponse = MockStreamTextResponseWriter()

        pipeTextStreamToResponse(
            response: mockResponse,
            status: 200,
            statusText: "OK",
            headers: ["Custom-Header": "test"],
            textStream: makeTextStream(from: ["test-data"])
        )

        await mockResponse.waitForEnd()

        #expect(mockResponse.statusCode == 200)
        #expect(mockResponse.statusMessage == "OK")
        #expect(mockResponse.headers == [
            "content-type": "text/plain; charset=utf-8",
            "custom-header": "test",
        ])
        #expect(mockResponse.decodedChunks() == ["test-data"])
    }
}

private func makeTextStream(from chunks: [String]) -> AsyncThrowingStream<String, Error> {
    AsyncThrowingStream { continuation in
        for chunk in chunks {
            continuation.yield(chunk)
        }
        continuation.finish()
    }
}

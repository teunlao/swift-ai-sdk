import Testing
@testable import SwiftAISDK

/**
 Tests for `createTextStreamResponse`.

 Port of `@ai-sdk/ai/src/text-stream/create-text-stream-response.test.ts`.
 */
@Suite("CreateTextStreamResponse Tests")
struct CreateTextStreamResponseTests {

    @Test("should create a response with correct headers and encoded stream")
    func testCreateResponse() async throws {
        let response = createTextStreamResponse(
            status: 200,
            statusText: "OK",
            headers: ["Custom-Header": "test"],
            textStream: makeTextStream(from: ["test-data"])
        )

        #expect(response.initOptions?.status == 200)
        #expect(response.initOptions?.statusText == "OK")

        let headers = response.initOptions?.headers ?? [:]
        #expect(headers["content-type"] == "text/plain; charset=utf-8")
        #expect(headers["Custom-Header"] == "test")

        var collectedChunks: [String] = []
        for try await chunk in response.stream {
            collectedChunks.append(chunk)
        }

        #expect(collectedChunks == ["test-data"])
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

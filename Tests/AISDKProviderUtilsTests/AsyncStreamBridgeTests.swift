import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("Async Stream Bridge Utilities")
struct AsyncStreamBridgeTests {
    @Test("convertArrayToAsyncIterable yields array in order")
    func arrayToAsyncIterableYieldsValues() async {
        let values = [1, 2, 3, 4]
        let stream = convertArrayToAsyncIterable(values)

        var collected: [Int] = []
        for await value in stream {
            collected.append(value)
        }

        #expect(collected == values)
    }

    @Test("convertAsyncIteratorToReadableStream bridges iterator to stream")
    func asyncIteratorToReadableStream() async throws {
        let values = ["one", "two", "three"]
        let stream = convertArrayToAsyncIterable(values)
        let iterator = stream.makeAsyncIterator()

        let readable = convertAsyncIteratorToReadableStream(iterator)
        let collected = try await convertReadableStreamToArray(readable)

        #expect(collected == values)
    }

    @Test("convertArrayToReadableStream creates stream that can be collected")
    func arrayToReadableStreamRoundtrip() async throws {
        let values = [UUID(), UUID(), UUID()]
        let stream = convertArrayToReadableStream(values)
        let collected = try await convertReadableStreamToArray(stream)

        #expect(collected == values)
    }

    @Test("convertAsyncIterableToArray collects async sequence")
    func asyncIterableToArrayCollectsSequence() async {
        let values = [42, 43, 44]
        let stream = convertArrayToAsyncIterable(values)
        let collected = await convertAsyncIterableToArray(stream)

        #expect(collected == values)
    }

    @Test("convertResponseStreamToArray collects string chunks")
    func responseStreamToArrayCollectsChunks() async throws {
        let response = makeResponse(
            body: .stream(AsyncThrowingStream { continuation in
                ["chunk-1", "chunk-2", "chunk-3"].forEach { value in
                    continuation.yield(Data(value.utf8))
                }
                continuation.finish()
            })
        )

        let collected = try await convertResponseStreamToArray(response)
        #expect(collected == ["chunk-1", "chunk-2", "chunk-3"])
    }

    @Test("convertResponseStreamToArray preserves multibyte characters across chunk boundaries")
    func responseStreamToArraySupportsMultibyte() async throws {
        let thumbsUp = "👍"
        let data = Array(thumbsUp.data(using: .utf8)!)

        let response = makeResponse(
            body: .stream(AsyncThrowingStream { continuation in
                continuation.yield(Data(data.prefix(2)))
                continuation.yield(Data(data.suffix(from: 2)))
                continuation.finish()
            })
        )

        let collected = try await convertResponseStreamToArray(response)
        #expect(collected == [thumbsUp])
    }

    @Test("convertResponseStreamToArray handles buffered data")
    func responseStreamToArrayHandlesBufferedData() async throws {
        let response = makeResponse(
            body: .data(Data("buffered".utf8))
        )

        let collected = try await convertResponseStreamToArray(response)
        #expect(collected == ["buffered"])
    }

    @Test("convertResponseStreamToArray returns empty array for missing body")
    func responseStreamToArrayHandlesEmptyBody() async {
        let response = makeResponse(body: .none)
        await #expect(throws: ResponseStreamConversionError.missingBody) {
            _ = try await convertResponseStreamToArray(response)
        }
    }

    private func makeResponse(body: ProviderHTTPResponseBody) -> ProviderHTTPResponse {
        let url = URL(string: "https://example.com")!
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!

        return ProviderHTTPResponse(
            url: url,
            httpResponse: httpResponse,
            body: body
        )
    }
}

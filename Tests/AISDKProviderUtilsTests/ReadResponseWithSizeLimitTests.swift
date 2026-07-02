import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("readResponseWithSizeLimit")
struct ReadResponseWithSizeLimitTests {
    @Test("reads response data within limit")
    func readsResponseWithinLimit() async throws {
        let response = makeProviderResponse(
            body: .data(Data([1, 2, 3, 4, 5, 6, 7, 8])),
            headers: ["Content-Length": "8"]
        )

        let result = try await readResponseWithSizeLimit(
            response: response,
            url: "http://example.com/file",
            maxBytes: 100
        )

        #expect(result == Data([1, 2, 3, 4, 5, 6, 7, 8]))
    }

    @Test("rejects early when Content-Length exceeds limit")
    func rejectsOversizedContentLength() async throws {
        let response = makeProviderResponse(
            body: .data(Data(repeating: 1, count: 10)),
            headers: ["Content-Length": "1000"]
        )

        do {
            _ = try await readResponseWithSizeLimit(
                response: response,
                url: "http://example.com/large",
                maxBytes: 100
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.message.contains("Content-Length: 1000"))
        }
    }

    @Test("rejects when streamed bytes exceed limit")
    func rejectsOversizedStream() async throws {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 42, count: 40))
            continuation.yield(Data(repeating: 42, count: 40))
            continuation.finish()
        }

        let response = makeProviderResponse(body: .stream(stream))

        do {
            _ = try await readResponseWithSizeLimit(
                response: response,
                url: "http://example.com/streaming",
                maxBytes: 50
            )
            Issue.record("Expected DownloadError")
        } catch let error as DownloadError {
            #expect(error.message.contains("exceeded maximum size of 50 bytes"))
        }
    }

    @Test("handles empty body")
    func handlesEmptyBody() async throws {
        let response = makeProviderResponse(body: .none)
        let result = try await readResponseWithSizeLimit(
            response: response,
            url: "http://example.com/empty",
            maxBytes: 100
        )

        #expect(result.isEmpty)
    }
}

private func makeProviderResponse(
    body: ProviderHTTPResponseBody,
    statusCode: Int = 200,
    headers: [String: String] = [:],
    url: String = "https://example.com/file"
) -> ProviderHTTPResponse {
    let responseURL = URL(string: url)!
    let httpResponse = HTTPURLResponse(
        url: responseURL,
        statusCode: statusCode,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    )!

    return ProviderHTTPResponse(
        url: responseURL,
        httpResponse: httpResponse,
        body: body
    )
}

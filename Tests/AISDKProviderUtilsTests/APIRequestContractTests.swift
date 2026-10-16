import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("API request contracts")
struct APIRequestContractTests {
    private actor RequestCapture {
        private(set) var requests: [URLRequest] = []
        private(set) var bodies: [Data] = []

        func record(_ request: URLRequest) {
            requests.append(request)
            if let stream = request.httpBodyStream {
                bodies.append(readAll(stream))
            }
        }

        private func readAll(_ stream: InputStream) -> Data {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(buffer, count: count)
            }
            return data
        }
    }

    private static func response(
        _ request: URLRequest,
        statusCode: Int = 200,
        body: ProviderHTTPResponseBody = .data(Data("{}".utf8))
    ) -> FetchResponse {
        FetchResponse(
            body: body,
            urlResponse: HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }

    private static let anyJSON = FlexibleSchema(jsonSchema(["type": "object"]))

    @Test("a successful stream that fails mid-read surfaces a retryable APICallError")
    func midStreamNetworkFailureIsRetryable() async throws {
        let body = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("data: {\"a\":1}\n\n".utf8))
            continuation.finish(throwing: URLError(.networkConnectionLost))
        }

        let result = try await postJsonToAPI(
            url: "https://api.example.com/stream",
            body: ["stream": true],
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: Self.anyJSON),
            fetch: { request in Self.response(request, body: .stream(body)) }
        )

        var parsedChunks = 0
        do {
            for try await chunk in result.value {
                if case .success = chunk { parsedChunks += 1 }
            }
            Issue.record("Expected the stream to fail")
        } catch let error as APICallError {
            #expect(parsedChunks == 1)
            #expect(error.isRetryable)
            #expect(error.statusCode == 200)
            #expect(error.cause is URLError)
        }
    }

    @Test("a connection failure becomes a retryable APICallError")
    func connectionFailureIsRetryable() async throws {
        let error = await #expect(throws: APICallError.self) {
            _ = try await postJsonToAPI(
                url: "https://api.example.com/chat",
                body: ["a": 1],
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
                fetch: { _ in throw URLError(.cannotConnectToHost) }
            )
        }
        #expect(error?.isRetryable == true)
    }

    @Test("getFromAPI validates untrusted URLs and withholds credentials from other origins")
    func getFromAPIValidatesUntrustedURLs() async throws {
        let capture = RequestCapture()
        let fetch: FetchFunction = { request in
            await capture.record(request)
            return Self.response(request)
        }

        await #expect(throws: DownloadError.self) {
            _ = try await getFromAPI(
                url: "http://169.254.169.254/latest",
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
                fetch: fetch,
                validateUrl: true
            )
        }

        _ = try await getFromAPI(
            url: "https://cdn.example.com/result.json",
            headers: ["Authorization": "Bearer key"],
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
            fetch: fetch,
            validateUrl: true,
            credentialedOrigin: "https://api.example.com"
        )

        let requests = await capture.requests
        #expect(requests.count == 1)
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == nil)
        #expect(requests[0].value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-provider-utils/") == true)
    }

    @Test("deleteFromAPI sends a DELETE request and maps failures through the error handler")
    func deleteFromAPISendsDelete() async throws {
        let capture = RequestCapture()

        let result = try await deleteFromAPI(
            url: "https://api.example.com/files/file-1",
            headers: ["Authorization": "Bearer key"],
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
            fetch: { request in
                await capture.record(request)
                return Self.response(request, body: .data(Data(#"{"deleted":true}"#.utf8)))
            }
        )

        #expect(result.value == ["deleted": true])
        let request = try #require(await capture.requests.first)
        #expect(request.httpMethod == "DELETE")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")

        let error = await #expect(throws: APICallError.self) {
            _ = try await deleteFromAPI(
                url: "https://api.example.com/files/missing",
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
                fetch: { request in Self.response(request, statusCode: 404) }
            )
        }
        #expect(error?.statusCode == 404)
    }

    @Test("postMultipartStreamToAPI streams parts in order and reports placeholders for files")
    func postMultipartStreamToAPIStreamsParts() async throws {
        let capture = RequestCapture()
        let fileStream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("hello ".utf8))
            continuation.yield(Data("world".utf8))
            continuation.finish()
        }

        _ = try await postMultipartStreamToAPI(
            url: "https://api.example.com/files",
            parts: [
                .field(name: "expires_after", value: "3600"),
                .file(name: "file", filename: "a\"b.txt", mediaType: "text/plain", content: .stream(fileStream)),
            ],
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
            fetch: { request in
                await capture.record(request)
                return Self.response(request)
            }
        )

        let request = try #require(await capture.requests.first)
        let contentType = try #require(request.value(forHTTPHeaderField: "Content-Type"))
        let boundary = try #require(contentType.components(separatedBy: "boundary=").last)
        #expect(contentType.hasPrefix("multipart/form-data; boundary=ai-sdk-multipart-"))

        let body = String(decoding: try #require(await capture.bodies.first), as: UTF8.self)
        #expect(body == [
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"expires_after\"\r\n\r\n3600\r\n",
            "--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"a\\\"b.txt\"\r\nContent-Type: text/plain\r\n\r\nhello world\r\n",
            "--\(boundary)--\r\n",
        ].joined())

        let error = await #expect(throws: APICallError.self) {
            _ = try await postMultipartStreamToAPI(
                url: "https://api.example.com/files",
                parts: [.file(name: "file", filename: "a.txt", content: .data(Data("x".utf8)))],
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON),
                fetch: { request in Self.response(request, statusCode: 500) }
            )
        }
        #expect(error?.requestBodyValues as? [String: String] == ["file": "<file:a.txt>"])
    }
}

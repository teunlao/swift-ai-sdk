#if canImport(Network)
import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

/// Transport contracts exercised against a real HTTP server on 127.0.0.1.
@Suite("URLSession transport", .serialized, .timeLimit(.minutes(1)))
struct URLSessionTransportTests {
    private actor PathLog {
        private(set) var paths: [String] = []
        private(set) var requests: [LoopbackHTTPRequest] = []
        func record(_ request: LoopbackHTTPRequest) {
            paths.append(request.path)
            requests.append(request)
        }
    }

    private static let anyJSON = FlexibleSchema(jsonSchema(["type": "object"]))

    @Test("validated fetches never let the transport follow a redirect")
    func validatedFetchesDoNotFollowRedirects() async throws {
        let log = PathLog()
        let server = try await LoopbackHTTPServer { connection in
            while let request = try? await connection.readRequest() {
                await log.record(request)
                switch request.path {
                case "/start":
                    try? await connection.sendResponse(status: 302, headers: ["Location": "/final"])
                default:
                    try? await connection.sendResponse(status: 200, body: Data("ok".utf8))
                }
            }
        }
        defer { server.stop() }

        await #expect(throws: DownloadError.self) {
            _ = try await fetchWithValidatedEndpoint(
                request: URLRequest(url: URL(string: "\(server.origin)/start")!),
                trustedOrigin: server.origin
            )
        }
        #expect(await log.paths == ["/start"])

        let response = try await fetchWithValidatedRedirects(url: "\(server.origin)/start", trustedOrigin: server.origin)
        #expect(response.statusCode == 200)
        #expect(try await response.body.collectData() == Data("ok".utf8))
        #expect(await log.paths == ["/start", "/start", "/final"])
    }

    @Test("an injected fetch that follows redirects itself fails closed")
    func injectedFollowingFetchFailsClosed() async throws {
        let server = try await LoopbackHTTPServer { connection in
            while let request = try? await connection.readRequest() {
                if request.path == "/start" {
                    try? await connection.sendResponse(status: 302, headers: ["Location": "/final"])
                } else {
                    try? await connection.sendResponse(status: 200, body: Data("ok".utf8))
                }
            }
        }
        defer { server.stop() }

        let followingFetch: FetchFunction = { request in
            let (data, response) = try await URLSession.shared.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }

        await #expect(throws: DownloadError.self) {
            _ = try await fetchWithValidatedRedirects(
                url: "\(server.origin)/start",
                fetch: followingFetch,
                trustedOrigin: server.origin
            )
        }
    }

    @Test("downloads neither send nor store ambient cookies")
    func downloadsIgnoreAmbientCookies() async throws {
        let log = PathLog()
        let server = try await LoopbackHTTPServer { connection in
            while let request = try? await connection.readRequest() {
                await log.record(request)
                try? await connection.sendResponse(
                    status: 200,
                    headers: ["Set-Cookie": "planted=1; Path=/"],
                    body: Data("ok".utf8)
                )
            }
        }
        defer { server.stop() }

        let url = URL(string: "\(server.origin)/file")!
        let seeded = HTTPCookie(properties: [
            .name: "session", .value: "secret", .domain: "127.0.0.1", .path: "/",
        ])!
        HTTPCookieStorage.shared.setCookie(seeded)
        defer {
            HTTPCookieStorage.shared.cookies(for: url)?.forEach(HTTPCookieStorage.shared.deleteCookie)
        }

        _ = try await fetchUntrustedUrl(url: url.absoluteString, trustedOrigin: server.origin)

        #expect(await log.requests.first?.headers["cookie"] == nil)
        #expect(HTTPCookieStorage.shared.cookies(for: url)?.contains { $0.name == "planted" } != true)
    }

    @Test("a lagging consumer pauses the response transfer and cancelling it closes the connection")
    func responseBodyHasBackpressure() async throws {
        let total = 64 << 20
        let sent = LockedCounter()
        let closed = AsyncStream<Void>.makeStream()
        let server = try await LoopbackHTTPServer { connection in
            guard (try? await connection.readRequest()) != nil else { return }
            try? await connection.sendHead(status: 200, headers: ["Content-Length": String(total)])
            let chunk = Data(count: 64 << 10)
            while sent.value < total, (try? await connection.send(chunk)) != nil {
                sent.add(chunk.count)
            }
            await connection.waitUntilClosed()
            closed.continuation.yield()
        }
        defer { server.stop() }

        let url = URL(string: "\(server.origin)/large")!
        // The reader owns the response: when it ends, its body stream is released.
        let reader = Task {
            let response = try await defaultFetchFunction()(URLRequest(url: url))
            var iterator = response.body.makeStream().makeAsyncIterator()
            _ = try await iterator.next()
            try await Task.sleep(nanoseconds: .max)
        }

        let stalledAt = try await waitUntilStable { sent.value }
        #expect(stalledAt < total / 4)

        reader.cancel()
        var closedEvents = closed.stream.makeAsyncIterator()
        _ = await closedEvents.next()
    }

    @Test("cancelling an event-stream consumer closes the provider connection")
    func eventStreamCancellationReachesTheNetwork() async throws {
        let closed = AsyncStream<Void>.makeStream()
        let server = try await LoopbackHTTPServer { connection in
            guard let request = try? await connection.readRequest() else { return }
            _ = try? await connection.readBody(of: request)
            try? await connection.sendHead(status: 200, headers: ["Content-Type": "text/event-stream"])
            try? await connection.send(Data("data: {\"n\":1}\n\n".utf8))
            await connection.waitUntilClosed()
            closed.continuation.yield()
        }
        defer { server.stop() }

        let result = try await postJsonToAPI(
            url: "\(server.origin)/stream",
            body: ["stream": true],
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createEventSourceResponseHandler(chunkSchema: Self.anyJSON)
        )

        let firstEvent = AsyncStream<Void>.makeStream()
        let consumer = Task {
            for try await _ in result.value {
                firstEvent.continuation.yield()
            }
        }
        var events = firstEvent.stream.makeAsyncIterator()
        _ = await events.next()

        consumer.cancel()
        var closedEvents = closed.stream.makeAsyncIterator()
        _ = await closedEvents.next()
    }

    @Test("a multipart upload pulls the source only as fast as the server reads")
    func multipartUploadHasBackpressure() async throws {
        let chunkSize = 64 << 10
        let total = 64 << 20
        let pulled = LockedCounter()
        let release = AsyncStream<Void>.makeStream()
        let server = try await LoopbackHTTPServer { connection in
            guard (try? await connection.readRequest()) != nil else { return }
            var waits = release.stream.makeAsyncIterator()
            _ = await waits.next()
            try? await connection.sendResponse(status: 413, body: Data(#"{"error":"too large"}"#.utf8))
            await connection.close()
        }
        defer { server.stop() }

        let source = AsyncThrowingStream<Data, Error> {
            guard pulled.value < total else { return nil }
            pulled.add(chunkSize)
            return Data(count: chunkSize)
        }

        let upload = Task {
            try await postMultipartStreamToAPI(
                url: "\(server.origin)/files",
                parts: [.file(name: "file", filename: "big.bin", content: .stream(source))],
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON)
            )
        }

        let stalledAt = try await waitUntilStable { pulled.value }
        #expect(stalledAt < total / 4)

        release.continuation.yield()
        let error = await #expect(throws: APICallError.self) { try await upload.value }
        #expect(error?.statusCode == 413, "cause: \(String(describing: error?.cause))")
    }

    @Test("a failing multipart source fails the upload even when the server accepts the body")
    func multipartSourceFailureFailsTheUpload() async throws {
        struct SourceFailure: Error {}

        let server = try await LoopbackHTTPServer { connection in
            guard let request = try? await connection.readRequest() else { return }
            _ = try? await connection.readBody(of: request)
            try? await connection.sendResponse(status: 200, body: Data("{}".utf8))
        }
        defer { server.stop() }

        let source = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data("partial".utf8))
            continuation.finish(throwing: SourceFailure())
        }

        await #expect(throws: SourceFailure.self) {
            _ = try await postMultipartStreamToAPI(
                url: "\(server.origin)/files",
                parts: [.file(name: "file", content: .stream(source))],
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON)
            )
        }
    }

    @Test("a failed multipart upload cancels the active and unread part streams before returning")
    func failedMultipartUploadReleasesSources() async throws {
        // A stopped server leaves a closed port: the fetch itself fails.
        let server = try await LoopbackHTTPServer { _ in }
        server.stop()
        try await Task.sleep(nanoseconds: 50_000_000)

        let terminated = LockedCounter()
        func openSource(yieldingFirst: Bool) -> AsyncThrowingStream<Data, Error> {
            AsyncThrowingStream { continuation in
                if yieldingFirst {
                    continuation.yield(Data("first".utf8))
                }
                continuation.onTermination = { _ in terminated.add(1) }
            }
        }

        let error = await #expect(throws: APICallError.self) {
            _ = try await postMultipartStreamToAPI(
                url: "\(server.origin)/files",
                parts: [
                    .file(name: "a", content: .stream(openSource(yieldingFirst: true))),
                    .file(name: "b", content: .stream(openSource(yieldingFirst: false))),
                ],
                failedResponseHandler: createStatusCodeErrorResponseHandler(),
                successfulResponseHandler: createJsonResponseHandler(responseSchema: Self.anyJSON)
            )
        }
        #expect(error?.isRetryable == true)
        #expect(terminated.value == 2)
    }

    @Test("a download host resolving to a reserved address is rejected before any request")
    func downloadRejectsHostResolvingToReservedAddress() async throws {
        // macOS maps `broadcasthost` to 255.255.255.255 in /etc/hosts; the name itself passes the string checks.
        let error = await #expect(throws: DownloadError.self) {
            _ = try await downloadBlob(url: "http://broadcasthost/file")
        }
        #expect(error?.url == "broadcasthost")
    }
}
#endif

#if canImport(Network)
import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("defaultFetchFunction", .timeLimit(.minutes(1)))
struct DefaultFetchFunctionTests {
    @Test("API redirects preserve caller headers only on the original origin", arguments: [302, 307, 308])
    func redirectsIsolateCallerHeaders(status: Int) async throws {
        let received = AsyncStream<LoopbackHTTPRequest>.makeStream()
        let destination = try await LoopbackHTTPServer { connection in
            guard let request = try? await connection.readRequest() else { return }
            let body = (try? await connection.readBody(of: request)) ?? Data()
            received.continuation.yield(request)
            try? await connection.sendResponse(status: 200, headers: ["Connection": "close"], body: body)
            await connection.close()
        }
        defer { destination.stop() }
        let source = try await LoopbackHTTPServer { connection in
            guard let request = try? await connection.readRequest() else { return }
            _ = try? await connection.readBody(of: request)
            if request.path == "/same" { received.continuation.yield(request) }
            try? await connection.sendResponse(status: status, headers: [
                "Connection": "close",
                "Location": request.path == "/start" ? "/same" : "\(destination.origin)/final"
            ])
            await connection.close()
        }
        defer { source.stop() }
        var request = URLRequest(url: URL(string: "\(source.origin)/start")!)
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.allHTTPHeaderFields = ["Authorization": "Bearer secret", "x-key": "secret", "x-private": "secret", "User-Agent": "redirect-test"]
        let response = try await defaultFetchFunction()(request)
        #expect((response.urlResponse as? HTTPURLResponse)?.statusCode == 200)
        var data = Data()
        if case .stream(let body) = response.body { for try await chunk in body { data.append(chunk) } }
        #expect(data == (status == 302 ? Data() : Data("{}".utf8)))
        var requests = received.stream.makeAsyncIterator()
        let sameOrigin = try #require(await requests.next())
        #expect(sameOrigin.headers["x-key"] == "secret")
        let crossOrigin = try #require(await requests.next())
        #expect(crossOrigin.path == "/final")
        #expect(crossOrigin.method == (status == 302 ? "GET" : "POST"))
        #expect(crossOrigin.headers["authorization"] == nil)
        #expect(crossOrigin.headers["x-key"] == nil)
        #expect(crossOrigin.headers["x-private"] == nil)
        #expect(crossOrigin.headers["user-agent"] == "redirect-test")
    }

    @Test("releasing an unread body stream stops the transfer")
    func releasingBodyStopsTransfer() async throws {
        let closed = AsyncStream<Void>.makeStream()
        let server = try await LoopbackHTTPServer { connection in
            guard (try? await connection.readRequest()) != nil else { return }
            try? await connection.sendHead(status: 200, headers: ["Content-Type": "application/octet-stream"])
            let chunk = Data(repeating: 0x2A, count: 64 * 1024)
            while (try? await connection.send(chunk)) != nil {}
            closed.continuation.yield()
        }
        defer { server.stop() }

        do {
            let response = try await defaultFetchFunction()(URLRequest(url: URL(string: "\(server.origin)/endless")!))
            guard case .stream = response.body else {
                Issue.record("Expected a streamed body")
                return
            }
        }

        var closedEvents = closed.stream.makeAsyncIterator()
        _ = await closedEvents.next()
    }
}
#endif

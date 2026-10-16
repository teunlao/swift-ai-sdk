#if canImport(Network)
import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("defaultFetchFunction", .timeLimit(.minutes(1)))
struct DefaultFetchFunctionTests {
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

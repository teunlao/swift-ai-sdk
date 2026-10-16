import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("defaultFetchFunction")
struct DefaultFetchFunctionTests {
    @Test("terminating the body stream stops the read")
    func terminatingStreamStopsRead() async throws {
        let (stopped, stoppedContinuation) = AsyncStream<Void>.makeStream()
        EndlessResponseProtocol.onStop.set { stoppedContinuation.yield() }
        URLProtocol.registerClass(EndlessResponseProtocol.self)
        defer { URLProtocol.unregisterClass(EndlessResponseProtocol.self) }

        let request = URLRequest(url: URL(string: "https://\(EndlessResponseProtocol.host)/endless")!)
        let response = try await defaultFetchFunction()(request)
        guard case .stream(let body) = response.body else {
            Issue.record("Expected a streamed body")
            return
        }

        let (firstChunk, firstChunkContinuation) = AsyncStream<Void>.makeStream()
        let consumer = Task {
            for try await _ in body { firstChunkContinuation.yield() }
        }
        for await _ in firstChunk { break }
        consumer.cancel()

        let didStop = await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in stopped { return true }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: 30_000_000_000)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }

        #expect(didStop)
    }
}

/// Serves an endless response on a private host and reports when URLSession stops loading it.
private final class EndlessResponseProtocol: URLProtocol, @unchecked Sendable {
    static let host = "endless.default-fetch-function.test"

    final class StopCallback: @unchecked Sendable {
        private let lock = NSLock()
        private var callback: (@Sendable () -> Void)?
        func set(_ callback: @escaping @Sendable () -> Void) { lock.withLock { self.callback = callback } }
        func fire() { lock.withLock { callback }?() }
    }

    static let onStop = StopCallback()

    private let stateLock = NSLock()
    private var stopped = false

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == host
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/octet-stream"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        sendChunk()
    }

    override func stopLoading() {
        stateLock.withLock { stopped = true }
        Self.onStop.fire()
    }

    private func sendChunk() {
        guard !stateLock.withLock({ stopped }) else { return }
        client?.urlProtocol(self, didLoad: Data(repeating: 0x2A, count: 64 * 1024))
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(10)) { [weak self] in
            self?.sendChunk()
        }
    }
}

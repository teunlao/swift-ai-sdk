import Foundation
import Testing
@testable import AISDKProviderUtils

@Suite("cancelResponseBody")
struct CancelResponseBodyTests {
    @Test("cancels stream bodies to release the connection")
    func cancelsStreamBody() async throws {
        let probe = StreamTerminationProbe()
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data([1, 2, 3]))
            continuation.onTermination = { @Sendable termination in
                Task {
                    await probe.record(termination)
                }
            }
        }

        await cancelResponseBody(makeResponse(body: .stream(stream)))

        switch await probe.waitForTermination() {
        case .cancelled:
            break
        default:
            Issue.record("Expected stream cancellation")
        }
    }

    @Test("is a no-op for missing and buffered bodies")
    func noopsForMissingAndBufferedBodies() async {
        await cancelResponseBody(makeResponse(body: .none))
        await cancelResponseBody(makeResponse(body: .data(Data([1, 2, 3]))))
    }

    @Test("swallows stream errors so the original rejection is preserved")
    func swallowsStreamErrors() async {
        let stream = AsyncThrowingStream<Data, Error> { continuation in
            continuation.finish(throwing: CancelResponseBodyTestError())
        }

        await cancelResponseBody(makeResponse(body: .stream(stream)))
    }

    private func makeResponse(body: ProviderHTTPResponseBody) -> ProviderHTTPResponse {
        let url = URL(string: "https://example.com/file")!
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

private actor StreamTerminationProbe {
    private var termination: AsyncThrowingStream<Data, Error>.Continuation.Termination?
    private var waiter: CheckedContinuation<AsyncThrowingStream<Data, Error>.Continuation.Termination, Never>?

    func record(_ termination: AsyncThrowingStream<Data, Error>.Continuation.Termination) {
        self.termination = termination
        waiter?.resume(returning: termination)
        waiter = nil
    }

    func waitForTermination() async -> AsyncThrowingStream<Data, Error>.Continuation.Termination {
        if let termination {
            return termination
        }

        return await withCheckedContinuation { continuation in
            waiter = continuation
        }
    }
}

private struct CancelResponseBodyTestError: Error {}

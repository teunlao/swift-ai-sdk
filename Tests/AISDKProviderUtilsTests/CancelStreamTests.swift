import Foundation
import Testing
import AISDKProviderUtils

@Suite("Native stream cancellation")
struct CancelStreamTests {
    private actor Producer {
        private(set) var started = false
        func begin() { started = true }
    }

    @Test("cancelling an idle throwing unfolding source does not start its producer")
    func cancelIdleThrowingSource() async throws {
        let producer = Producer()
        let release = DelayedPromise<Void>()
        let source = AsyncThrowingStream<Int, Error>(unfolding: {
            await producer.begin()
            try await release.task.value
            return 1
        })
        let cleanup = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            release.resolve(())
        }
        defer { cleanup.cancel(); release.resolve(()) }
        await cancelStream(source)
        #expect(await producer.started == false)
        var iterator = source.makeAsyncIterator()
        #expect(try await iterator.next() == nil)
    }

    @Test("cancelling an idle nonthrowing unfolding source does not start its producer")
    func cancelIdleSource() async throws {
        let producer = Producer()
        let release = DelayedPromise<Void>()
        let source = AsyncStream<Int>(unfolding: {
            await producer.begin()
            _ = try? await release.task.value
            return 1
        })
        let cleanup = Task {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            release.resolve(())
        }
        defer { cleanup.cancel(); release.resolve(()) }
        await cancelStream(source)
        #expect(await producer.started == false)
        var iterator = source.makeAsyncIterator()
        #expect(await iterator.next() == nil)
    }
}

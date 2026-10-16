import Foundation

public func createSSEStreamWithKeepAlive(
    stream: AsyncThrowingStream<String, Error>,
    keepAliveMs: Double?
) throws -> AsyncThrowingStream<String, Error> {
    guard let keepAliveMs else { return stream }
    guard keepAliveMs.isFinite, keepAliveMs > 0, keepAliveMs <= 2_147_483_647 else {
        throw KeepAliveError()
    }
    let state = SSEKeepAliveState(stream: stream, milliseconds: max(1, keepAliveMs.rounded(.towardZero)))
    return AsyncThrowingStream(unfolding: {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await state.next()
        } onCancel: {
            Task { await state.cancel() }
        }
    })
}

private struct KeepAliveError: LocalizedError {
    var errorDescription: String? {
        "keepAliveMs must be a positive finite timer duration no greater than 2147483647"
    }
}

private actor SSEKeepAliveState {
    private let stream: AsyncThrowingStream<String, Error>
    private let nanoseconds: UInt64
    private var queue: [String] = [": stream-open\n\n"]
    private var queueIndex = 0
    private var waiter: CheckedContinuation<String?, Error>?
    private var producer: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var ended = false
    private var failure: Error?
    private var commentPending = false

    init(stream: AsyncThrowingStream<String, Error>, milliseconds: Double) {
        self.stream = stream
        nanoseconds = UInt64(milliseconds * 1_000_000)
    }

    func next() async throws -> String? {
        if producer == nil && !ended {
            scheduleTimer()
            producer = Task {
                do {
                    for try await value in stream { receive(value) }
                    finish(nil)
                } catch { finish(error) }
            }
        }
        if queueIndex < queue.count {
            let value = queue[queueIndex]
            queueIndex += 1
            if queueIndex * 2 >= queue.count {
                queue.removeFirst(queueIndex)
                queueIndex = 0
            }
            if value == ": keep-alive\n\n" { commentPending = false }
            return value
        }
        if ended {
            if let failure { throw failure }
            return nil
        }
        return try await withCheckedThrowingContinuation { waiter = $0 }
    }

    func cancel() {
        producer?.cancel()
        finish(nil)
        queue.removeAll()
        queueIndex = 0
    }

    private func receive(_ value: String) {
        guard !ended else { return }
        emit(value)
        scheduleTimer()
    }

    private func emit(_ value: String) {
        if let waiter {
            self.waiter = nil
            waiter.resume(returning: value)
        } else { queue.append(value) }
    }

    private func scheduleTimer() {
        timer?.cancel()
        timer = Task {
            do { try await Task.sleep(nanoseconds: nanoseconds) }
            catch { return }
            guard !ended else { return }
            if !commentPending && queueIndex == queue.count {
                commentPending = waiter == nil
                emit(": keep-alive\n\n")
            }
            scheduleTimer()
        }
    }

    private func finish(_ error: Error?) {
        guard !ended else { return }
        ended = true
        failure = error
        timer?.cancel()
        timer = nil
        if let waiter {
            self.waiter = nil
            if let error { waiter.resume(throwing: error) }
            else { waiter.resume(returning: nil) }
        }
    }
}

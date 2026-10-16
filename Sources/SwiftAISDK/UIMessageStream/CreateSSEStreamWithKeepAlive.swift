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
    private let source: AsyncIterableStream<String>
    private let iterator: AsyncIterableStream<String>.AsyncIterator
    private let nanoseconds: UInt64
    private var openingPending = true
    private var lastActivity = DispatchTime.now().uptimeNanoseconds
    private var waiters: [CheckedContinuation<String?, Error>] = []
    private var pending: Result<String?, Error>?
    private var readTask: Task<Void, Never>?
    private var timer: Task<Void, Never>?
    private var timerID: UUID?
    private var ended = false
    private var failure: Error?

    init(stream: AsyncThrowingStream<String, Error>, milliseconds: Double) {
        let source = createAsyncIterableStream(source: stream)
        self.source = source
        iterator = source.makeAsyncIterator()
        nanoseconds = UInt64(milliseconds * 1_000_000)
    }

    func next() async throws -> String? {
        if ended {
            if let failure { throw failure }
            return nil
        }
        if openingPending {
            openingPending = false
            lastActivity = DispatchTime.now().uptimeNanoseconds
            return ": stream-open\n\n"
        }
        return try await withCheckedThrowingContinuation { continuation in
            waiters.append(continuation)
            if let pending {
                self.pending = nil
                deliver(pending)
            }
            serveDemand()
        }
    }

    func cancel() async {
        guard !ended else { return }
        ended = true
        timer?.cancel()
        timer = nil
        timerID = nil
        readTask?.cancel()
        pending = nil
        finishWaiters(nil)
        await source.cancel()
    }

    private func serveDemand() {
        guard !ended, !waiters.isEmpty else { return }
        if readTask == nil {
            let iterator = iterator
            readTask = Task { [weak self] in
                let result: Result<String?, Error>
                do { result = .success(try await iterator.next()) }
                catch { result = .failure(error) }
                await self?.receive(result)
            }
        }
        scheduleTimer()
    }

    private func receive(_ result: Result<String?, Error>) {
        readTask = nil
        guard !ended else { return }
        timer?.cancel()
        timer = nil
        timerID = nil
        lastActivity = DispatchTime.now().uptimeNanoseconds
        if waiters.isEmpty { pending = result }
        else { deliver(result) }
        serveDemand()
    }

    private func deliver(_ result: Result<String?, Error>) {
        switch result {
        case .success(let value?): waiters.removeFirst().resume(returning: value)
        case .success(nil):
            ended = true
            finishWaiters(nil)
        case .failure(let error):
            ended = true
            failure = error
            finishWaiters(error)
        }
    }

    private func scheduleTimer() {
        guard timer == nil else { return }
        let elapsed = DispatchTime.now().uptimeNanoseconds - lastActivity
        let delay = elapsed >= nanoseconds ? 0 : nanoseconds - elapsed
        let id = UUID()
        timerID = id
        timer = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: delay) }
            catch { return }
            await self?.heartbeat(id: id)
        }
    }

    private func heartbeat(id: UUID) {
        guard timerID == id else { return }
        timer = nil
        timerID = nil
        guard !ended, !waiters.isEmpty else { return }
        lastActivity = DispatchTime.now().uptimeNanoseconds
        waiters.removeFirst().resume(returning: ": keep-alive\n\n")
        if !waiters.isEmpty { scheduleTimer() }
    }

    private func finishWaiters(_ error: Error?) {
        let waiters = waiters
        self.waiters.removeAll()
        for waiter in waiters {
            if let error { waiter.resume(throwing: error) }
            else { waiter.resume(returning: nil) }
        }
    }

    deinit {
        timer?.cancel()
        readTask?.cancel()
        let source = source
        Task { await source.cancel() }
    }
}

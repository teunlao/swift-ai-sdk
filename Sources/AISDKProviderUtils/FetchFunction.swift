import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Default timeout interval for API calls.
///
/// `URLRequest` defaults to 60 seconds, which can cause long-running provider calls (e.g. large contexts)
/// to fail with `NSURLErrorDomain Code=-1001` before the upstream provider responds.
internal let PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL: TimeInterval = 24 * 60 * 60

/// Represents the result returned by a fetch function.
public struct FetchResponse: Sendable {
    public let body: ProviderHTTPResponseBody
    public let urlResponse: URLResponse

    public init(body: ProviderHTTPResponseBody, urlResponse: URLResponse) {
        self.body = body
        self.urlResponse = urlResponse
    }
}

/// Function type that executes an HTTP request and returns the response.
///
/// A fetch function honors `URLRequest.fetchRedirectMode`: with `.manual` or `.error`
/// it must return a redirect response instead of following it.
public typealias FetchFunction = @Sendable (URLRequest) async throws -> FetchResponse

/// How a fetch treats a redirect response. Port of `RequestInit.redirect`.
public enum FetchRedirectMode: String, Sendable {
    /// Redirects are followed by the fetch function.
    case follow
    /// The redirect response is returned; the caller validates `Location` before following it.
    case manual
    /// The redirect response is returned and the caller fails the request.
    case error
}

private let fetchRedirectModeKey = "ai-sdk.fetchRedirectMode"

extension URLRequest {
    /// Redirect policy the fetch function applies, carried with the request like
    /// `RequestInit.redirect`. Defaults to `.follow`.
    public var fetchRedirectMode: FetchRedirectMode {
        get {
            (URLProtocol.property(forKey: fetchRedirectModeKey, in: self) as? String)
                .flatMap(FetchRedirectMode.init(rawValue:)) ?? .follow
        }
        set {
            guard let mutable = (self as NSURLRequest).mutableCopy() as? NSMutableURLRequest else {
                return
            }
            URLProtocol.setProperty(newValue.rawValue, forKey: fetchRedirectModeKey, in: mutable)
            self = mutable as URLRequest
        }
    }
}

/// Creates the default fetch implementation backed by `URLSession`.
///
/// Like server-side `fetch`, it keeps no ambient state: no cookie jar, credential
/// store or response cache. It honors `URLRequest.fetchRedirectMode`, streams the
/// response body as it arrives, pauses the transfer while the consumer lags, and
/// cancels it when the consumer cancels or drops the body.
public func defaultFetchFunction() -> FetchFunction {
    { request in
        try await URLSessionFetch.perform(request)
    }
}

func fetchWithAbortCheck(
    fetch: @escaping FetchFunction,
    request: URLRequest,
    isAborted: (@Sendable () -> Bool)?
) async throws -> FetchResponse {
    guard let isAborted else {
        return try await fetch(request)
    }

    if isAborted() {
        throw CancellationError()
    }

    let response = try await withThrowingTaskGroup(of: FetchResponse.self) { group in
        group.addTask {
            try await fetch(request)
        }

        group.addTask {
            while true {
                if isAborted() {
                    throw CancellationError()
                }
                try await Task.sleep(nanoseconds: 50_000_000)
            }
        }

        do {
            guard let result = try await group.next() else {
                throw CancellationError()
            }

            group.cancelAll()
            while let _ = try? await group.next() {}
            return result
        } catch {
            group.cancelAll()
            while let _ = try? await group.next() {}
            throw error
        }
    }

    if isAborted() {
        throw CancellationError()
    }
    guard case .stream(let stream) = response.body else {
        return response
    }

    let body = AbortableResponseBody(stream: stream, isAborted: isAborted)
    return FetchResponse(
        body: .stream(AsyncThrowingStream { try await body.next() }),
        urlResponse: response.urlResponse
    )
}

private final class AbortableResponseBody: @unchecked Sendable {
    private let lock = NSLock()
    private var source: AsyncIteratorBox<AsyncThrowingStream<Data, Error>.AsyncIterator>?
    private var isAborted: (@Sendable () -> Bool)?
    private var observer: Task<Void, Never>?
    private var read: Task<Data?, Error>?
    private var cancelled = false

    init(stream: AsyncThrowingStream<Data, Error>, isAborted: @escaping @Sendable () -> Bool) {
        self.source = AsyncIteratorBox(stream.makeAsyncIterator())
        self.isAborted = isAborted
        // The stream owns the observer; the observer must not keep an abandoned body alive.
        self.observer = Task { [weak self] in
            while self?.checkAbort() == false {
                do {
                    try await Task.sleep(nanoseconds: 50_000_000)
                } catch {
                    return
                }
            }
        }
    }

    deinit {
        cancel()
    }

    private func checkAbort() -> Bool {
        guard let isAborted = lock.withLock({ self.isAborted }) else {
            return true
        }
        if isAborted() {
            cancel()
            return true
        }
        return false
    }

    func next() async throws -> Data? {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            _ = checkAbort()
            let task = try lock.withLock { () throws -> Task<Data?, Error>? in
                if cancelled {
                    throw CancellationError()
                }
                guard let source else { return nil }
                let task = Task { try await source.next() }
                read = task
                return task
            }
            guard let task else { return nil }
            let result = await task.result
            return try lock.withLock {
                read = nil
                if cancelled {
                    throw CancellationError()
                }
                switch result {
                case .success(.some(let chunk)):
                    return chunk
                case .success(nil), .failure:
                    source = nil
                    isAborted = nil
                    observer?.cancel()
                    observer = nil
                    return try result.get()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancelled = true
        let source = self.source
        self.source = nil
        isAborted = nil
        let read = self.read
        let observer = self.observer
        self.observer = nil
        lock.unlock()
        read?.cancel()
        observer?.cancel()
        if let source {
            Task {
                // Join the active pull before cancelling the iterator, including externally retained streams.
                _ = await read?.result
                withUnsafeCurrentTask { $0?.cancel() }
                _ = try? await source.next()
            }
        }
    }
}

// MARK: - URLSession transport

private enum URLSessionFetch {
    static let session: URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }()

    static func perform(_ request: URLRequest) async throws -> FetchResponse {
        let task = session.dataTask(with: request)
        let delegate = FetchTaskDelegate(redirectMode: request.fetchRedirectMode, task: task)
        task.delegate = delegate

        let response = try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                delegate.awaitResponse(continuation)
                task.resume()
            }
        } onCancel: {
            task.cancel()
        }

        return FetchResponse(body: .stream(delegate.body.makeStream()), urlResponse: response)
    }
}

/// Receives one data task's events. The task retains it until the task completes.
private final class FetchTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    let body: ResponseBodyBuffer
    private let redirectMode: FetchRedirectMode
    private let lock = NSLock()
    private var responseContinuation: CheckedContinuation<URLResponse, Error>?
    private var pendingResult: Result<URLResponse, Error>?

    init(redirectMode: FetchRedirectMode, task: URLSessionDataTask) {
        self.redirectMode = redirectMode
        self.body = ResponseBodyBuffer(task: task)
    }

    func awaitResponse(_ continuation: CheckedContinuation<URLResponse, Error>) {
        lock.lock()
        if let pendingResult {
            lock.unlock()
            continuation.resume(with: pendingResult)
            return
        }
        responseContinuation = continuation
        lock.unlock()
    }

    private func deliverResponse(_ result: Result<URLResponse, Error>) {
        lock.lock()
        guard pendingResult == nil else {
            lock.unlock()
            return
        }
        pendingResult = result
        let continuation = responseContinuation
        responseContinuation = nil
        lock.unlock()
        continuation?.resume(with: result)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // Without a followed redirect, the redirect response itself is delivered.
        completionHandler(redirectMode == .follow ? request : nil)
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        deliverResponse(.success(response))
        completionHandler(.allow)
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        body.append(data)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            deliverResponse(.failure(error))
        } else if let response = task.response {
            deliverResponse(.success(response))
        } else {
            deliverResponse(.failure(URLError(.badServerResponse)))
        }
        body.finish(error)
    }
}

/**
 Body chunks received for one data task, read on demand by the consumer.

 The transfer is suspended while more than `highWaterMark` bytes wait unread and
 resumed once the backlog drops below `lowWaterMark`. A cancelled consumer, or a
 body stream released unread, cancels the data task.
 */
private final class ResponseBodyBuffer: @unchecked Sendable {
    private static let highWaterMark = 1 << 20
    private static let lowWaterMark = 256 << 10

    private let lock = NSLock()
    private let task: URLSessionDataTask
    private var chunks: [Data] = []
    private var head = 0
    private var bufferedBytes = 0
    private var isSuspended = false
    private var completion: Result<Void, Error>?
    private var waiter: CheckedContinuation<Data?, Error>?

    init(task: URLSessionDataTask) {
        self.task = task
    }

    func makeStream() -> AsyncThrowingStream<Data, Error> {
        let release = CancelOnRelease(task: task)
        return AsyncThrowingStream {
            defer { withExtendedLifetime(release) {} }
            return try await self.next()
        }
    }

    func append(_ data: Data) {
        lock.lock()
        if let waiter {
            self.waiter = nil
            lock.unlock()
            waiter.resume(returning: data)
            return
        }
        chunks.append(data)
        bufferedBytes += data.count
        let shouldSuspend = !isSuspended && bufferedBytes >= Self.highWaterMark
        if shouldSuspend {
            isSuspended = true
        }
        lock.unlock()

        if shouldSuspend {
            task.suspend()
        }
    }

    func finish(_ error: Error?) {
        lock.lock()
        guard completion == nil else {
            lock.unlock()
            return
        }
        completion = error.map { .failure($0) } ?? .success(())
        let waiter = self.waiter
        self.waiter = nil
        lock.unlock()

        if let error {
            waiter?.resume(throwing: error)
        } else {
            waiter?.resume(returning: nil)
        }
    }

    private func next() async throws -> Data? {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data?, Error>) in
                lock.lock()

                if head < chunks.count {
                    let chunk = chunks[head]
                    head += 1
                    bufferedBytes -= chunk.count
                    if head == chunks.count {
                        chunks.removeAll(keepingCapacity: true)
                        head = 0
                    }
                    let shouldResume = isSuspended && bufferedBytes <= Self.lowWaterMark
                    if shouldResume {
                        isSuspended = false
                    }
                    lock.unlock()

                    if shouldResume {
                        task.resume()
                    }
                    continuation.resume(returning: chunk)
                    return
                }

                switch completion {
                case .success:
                    lock.unlock()
                    continuation.resume(returning: nil)
                case .failure(let error):
                    lock.unlock()
                    continuation.resume(throwing: error)
                case nil:
                    waiter = continuation
                    lock.unlock()
                }
            }
        } onCancel: {
            // Completion delivers URLError(.cancelled) to the waiting consumer.
            task.cancel()
        }
    }
}

/// Cancels the data task when the last reference to the body stream goes away.
private final class CancelOnRelease: @unchecked Sendable {
    private let task: URLSessionDataTask

    init(task: URLSessionDataTask) {
        self.task = task
    }

    deinit {
        task.cancel()
    }
}

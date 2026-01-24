import Foundation

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
public typealias FetchFunction = @Sendable (URLRequest) async throws -> FetchResponse

/// Creates the default fetch implementation backed by `URLSession`.
func defaultFetchFunction() -> FetchFunction {
    { request in
        let session = URLSession.shared

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            let (bytes, response) = try await session.bytes(for: request)
            let stream = makeDataStream(from: bytes)
            return FetchResponse(body: .stream(stream), urlResponse: response)
        } else {
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
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

    return try await withThrowingTaskGroup(of: FetchResponse.self) { group in
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
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeDataStream(from bytes: URLSession.AsyncBytes) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        Task {
            var buffer = Data()
            buffer.reserveCapacity(16_384)

            do {
                for try await byte in bytes {
                    buffer.append(byte)

                    if buffer.count >= 16_384 {
                        continuation.yield(buffer)
                        buffer.removeAll(keepingCapacity: true)
                    }
                }

                if !buffer.isEmpty {
                    continuation.yield(buffer)
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }
}

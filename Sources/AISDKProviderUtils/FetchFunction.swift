import Foundation

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

import Foundation

/// Represents the body of an HTTP response returned by a provider request.
public enum ProviderHTTPResponseBody: Sendable {
    case none
    case data(Data)
    case stream(AsyncThrowingStream<Data, Error>)

    /// Creates a stream for the body. For buffered data, the stream yields a single chunk.
    public func makeStream() -> AsyncThrowingStream<Data, Error> {
        switch self {
        case .none:
            return AsyncThrowingStream { continuation in
                continuation.finish()
            }
        case .data(let data):
            return AsyncThrowingStream { continuation in
                if !data.isEmpty {
                    continuation.yield(data)
                }
                continuation.finish()
            }
        case .stream(let stream):
            return stream
        }
    }

    /// Collects the body into a single `Data` object.
    public func collectData() async throws -> Data {
        switch self {
        case .none:
            return Data()
        case .data(let data):
            return data
        case .stream(let stream):
            var buffer = Data()
            for try await chunk in stream {
                buffer.append(chunk)
            }
            return buffer
        }
    }
}

/// Lightweight representation of an HTTP response for provider utilities.
public struct ProviderHTTPResponse: Sendable {
    public let url: URL
    public let httpResponse: HTTPURLResponse
    public let body: ProviderHTTPResponseBody
    public let statusText: String

    public init(
        url: URL,
        httpResponse: HTTPURLResponse,
        body: ProviderHTTPResponseBody,
        statusText: String? = nil
    ) {
        self.url = url
        self.httpResponse = httpResponse
        self.body = body
        if let statusText {
            self.statusText = statusText
        } else {
            let localized = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
            self.statusText = localized.isEmpty ? "\(httpResponse.statusCode)" : localized.capitalizingFirstLetter()
        }
    }

    public var statusCode: Int {
        httpResponse.statusCode
    }
}

private extension String {
    func capitalizingFirstLetter() -> String {
        self.capitalized
    }
}

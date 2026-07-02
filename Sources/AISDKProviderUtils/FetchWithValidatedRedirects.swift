import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Fetches a URL while enforcing the download URL guard on every redirect hop.
public func fetchWithValidatedRedirects(
    url: String,
    headers: [String: String]? = nil,
    isAborted: (@Sendable () -> Bool)? = nil,
    maxRedirects: Int = 10,
    fetch: FetchFunction? = nil
) async throws -> ProviderHTTPResponse {
    let fetchImpl = fetch ?? defaultManualRedirectFetchFunction()
    var currentUrl = url

    for _ in 0...maxRedirects {
        try validateDownloadUrl(currentUrl)

        guard let requestURL = URL(string: currentUrl) else {
            throw DownloadError(url: url, message: "Invalid URL: \(currentUrl)")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL

        if let headers {
            for (name, value) in headers {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let fetchResponse = try await fetchWithAbortCheck(
            fetch: fetchImpl,
            request: request,
            isAborted: isAborted
        )

        guard let httpResponse = fetchResponse.urlResponse as? HTTPURLResponse else {
            throw DownloadError(url: url, cause: URLError(.badServerResponse))
        }

        let response = ProviderHTTPResponse(
            url: requestURL,
            httpResponse: httpResponse,
            body: fetchResponse.body
        )

        if (300..<400).contains(httpResponse.statusCode),
           let location = httpResponse.value(forHTTPHeaderField: "Location") {
            await cancelResponseBody(response)

            guard let nextURL = URL(string: location, relativeTo: requestURL)?.absoluteURL else {
                throw DownloadError(url: url, message: "Invalid redirect URL: \(location)")
            }

            currentUrl = nextURL.absoluteString
            continue
        }

        return response
    }

    throw DownloadError(
        url: url,
        message: "Too many redirects (max \(maxRedirects))"
    )
}

private final class NoRedirectURLSessionDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

private func defaultManualRedirectFetchFunction() -> FetchFunction {
    { request in
        let delegate = NoRedirectURLSessionDelegate()
        let configuration = URLSessionConfiguration.default
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: nil
        )

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            let (bytes, response) = try await session.bytes(for: request)
            let stream = makeManualRedirectDataStream(
                from: bytes,
                session: session,
                delegate: delegate
            )
            return FetchResponse(body: .stream(stream), urlResponse: response)
        } else {
            defer { session.finishTasksAndInvalidate() }
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }
}

@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
private func makeManualRedirectDataStream(
    from bytes: URLSession.AsyncBytes,
    session: URLSession,
    delegate: NoRedirectURLSessionDelegate
) -> AsyncThrowingStream<Data, Error> {
    AsyncThrowingStream { continuation in
        let task = Task {
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

        continuation.onTermination = { @Sendable _ in
            task.cancel()
            session.invalidateAndCancel()
            _ = delegate
        }
    }
}

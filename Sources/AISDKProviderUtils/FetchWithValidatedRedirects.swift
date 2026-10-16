import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// Redirect status codes per the fetch spec. 300 and 304 are not redirects,
// even when a server attaches a Location header.
private let redirectStatusCodes: Set<Int> = [301, 302, 303, 307, 308]

/// How `fetchWithValidatedEndpoint` treats a redirect response.
public enum ValidatedEndpointRedirect: Sendable {
    /// A redirect fails the request.
    case error
    /// The redirect response is returned; the caller validates `Location` before following it.
    case manual
}

/**
 Fetches one validated URL without following redirects.

 Unless `request.url` is same-origin with `trustedOrigin` (a developer-configured
 origin that may resolve to a private address), it is checked with
 `validateDownloadUrl` first. Redirects are rejected by default; with `.manual`
 the redirect response is returned for the caller to validate.

 Swift port of `fetchWithValidatedEndpoint` from
 `@ai-sdk/provider-utils/src/fetch-with-validated-redirects.ts`. URLSession has
 no connect-time DNS hook, so an injected fetch is responsible for equivalent
 connect-time validation.
 */
public func fetchWithValidatedEndpoint(
    request: URLRequest,
    fetch: FetchFunction? = nil,
    trustedOrigin: String? = nil,
    redirect: ValidatedEndpointRedirect = .error,
    isAborted: (@Sendable () -> Bool)? = nil
) async throws -> ProviderHTTPResponse {
    guard let requestURL = request.url else {
        throw DownloadError(url: "", message: "Invalid URL: ")
    }
    let urlText = requestURL.absoluteString

    let isTrusted = trustedOrigin.map { isSameOrigin(urlText, $0) } ?? false
    if !isTrusted {
        try validateDownloadUrl(urlText)
    }

    let fetchResponse = try await fetchWithAbortCheck(
        fetch: fetch ?? defaultManualRedirectFetchFunction(),
        request: request,
        isAborted: isAborted
    )

    guard let httpResponse = fetchResponse.urlResponse as? HTTPURLResponse else {
        throw DownloadError(url: urlText, cause: URLError(.badServerResponse))
    }

    let response = ProviderHTTPResponse(
        url: requestURL,
        httpResponse: httpResponse,
        body: fetchResponse.body
    )

    if redirect == .error, redirectStatusCodes.contains(httpResponse.statusCode) {
        startCancellingResponseBody(response)
        throw DownloadError(
            url: urlText,
            message: "Redirect from \(urlText) was blocked"
        )
    }

    return response
}

/**
 Fetches a URL while enforcing the download guard on every hop.

 Redirects are followed manually so each hop is checked with `validateDownloadUrl`
 before it is requested. A hop that is same-origin with `trustedOrigin` (the
 developer-configured provider endpoint, never response data) skips validation.

 Request headers are sanitized with `sanitizeRequestHeaders` before the first
 request, and every caller header except `user-agent` is dropped on a redirect
 that crosses origin, so credentials in custom headers cannot reach a foreign
 host. Credentials still reach the first hop; use `fetchUntrustedUrl` for URLs
 that need first-hop credential isolation.

 The returned response is the final non-redirect response; the caller checks the
 status and reads the body.

 Swift port of `@ai-sdk/provider-utils/src/fetch-with-validated-redirects.ts`.

 - Throws: `DownloadError` if a hop is unsafe or the redirect limit is exceeded.
 */
public func fetchWithValidatedRedirects(
    url: String,
    headers: [String: String]? = nil,
    isAborted: (@Sendable () -> Bool)? = nil,
    maxRedirects: Int = 10,
    fetch: FetchFunction? = nil,
    trustedOrigin: String? = nil
) async throws -> ProviderHTTPResponse {
    let fetchImpl = fetch ?? defaultManualRedirectFetchFunction()
    var currentHeaders = headers.map(sanitizeRequestHeaders)
    var currentUrl = url

    for _ in 0...maxRedirects {
        let isTrustedHop = trustedOrigin.map { isSameOrigin(currentUrl, $0) } ?? false
        if !isTrustedHop {
            try validateDownloadUrl(currentUrl)
        }

        guard let requestURL = URL(string: currentUrl) else {
            throw DownloadError(url: url, message: "Invalid URL: \(currentUrl)")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL

        if let currentHeaders {
            for (name, value) in currentHeaders {
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

        if redirectStatusCodes.contains(httpResponse.statusCode),
           let location = httpResponse.value(forHTTPHeaderField: "Location"),
           !location.isEmpty {
            // Release the redirect body without waiting: cancellation may stay
            // pending while another consumer holds the stream.
            startCancellingResponseBody(response)

            guard let nextURL = URL(string: location, relativeTo: requestURL)?.absoluteURL else {
                throw DownloadError(url: url, message: "Invalid redirect URL: \(location)")
            }
            let nextUrl = nextURL.absoluteString

            if let headersBeforeRedirect = currentHeaders, !isSameOrigin(nextUrl, currentUrl) {
                currentHeaders = headersBeforeRedirect["user-agent"].map { ["user-agent": $0] } ?? [:]
            }

            currentUrl = nextUrl
            continue
        }

        return response
    }

    throw DownloadError(
        url: url,
        message: "Too many redirects (max \(maxRedirects))"
    )
}

private func startCancellingResponseBody(_ response: ProviderHTTPResponse) {
    Task {
        await cancelResponseBody(response)
    }
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

func defaultManualRedirectFetchFunction() -> FetchFunction {
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

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
 `validateDownloadUrl` first, and with the default transport its hostname must not
 resolve to a private address. Redirects are rejected by default; with `.manual`
 the redirect response is returned for the caller to validate.

 The fetch function receives the request with `fetchRedirectMode` set and must
 not follow redirects; a response for another URL fails the request. An injected
 fetch is responsible for its own connect-time DNS validation.

 Swift port of `fetchWithValidatedEndpoint` from
 `@ai-sdk/provider-utils/src/fetch-with-validated-redirects.ts`.
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
        if fetch == nil {
            try await validateResolvedDownloadHost(urlText)
        }
    }

    var hopRequest = request
    hopRequest.fetchRedirectMode = redirect == .error ? .error : .manual

    let response = try await fetchHop(
        hopRequest,
        url: urlText,
        fetch: fetch ?? defaultFetchFunction(),
        isAborted: isAborted
    )

    if redirect == .error, redirectStatusCodes.contains(response.statusCode) {
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
 (and, with the default transport, its resolved addresses) before it is requested.
 A hop that is same-origin with `trustedOrigin` (the developer-configured provider
 endpoint, never response data) skips validation. The fetch function receives each
 hop with `fetchRedirectMode == .manual`; a fetch that follows a redirect anyway
 cannot have that hop validated, so its response fails the request.

 Request headers are sanitized with `sanitizeRequestHeaders` before the first
 request, and every caller header except `user-agent` is dropped on a redirect
 that crosses origin, so credentials in custom headers cannot reach a foreign
 host. Credentials still reach the first hop; use `fetchUntrustedUrl` for URLs
 that need first-hop credential isolation.

 Hostname checks are not pinned to the connection, so they give no guarantee
 against DNS rebinding; constrain egress at the network layer for untrusted URLs.

 Swift port of `@ai-sdk/provider-utils/src/fetch-with-validated-redirects.ts`.

 - Throws: `DownloadError` if a hop is unsafe, cannot be validated, or the
   redirect limit is exceeded.
 */
public func fetchWithValidatedRedirects(
    url: String,
    headers: [String: String]? = nil,
    isAborted: (@Sendable () -> Bool)? = nil,
    maxRedirects: Int = 10,
    fetch: FetchFunction? = nil,
    trustedOrigin: String? = nil
) async throws -> ProviderHTTPResponse {
    let fetchImpl = fetch ?? defaultFetchFunction()
    var currentHeaders = headers.map(sanitizeRequestHeaders)
    var currentUrl = url

    for _ in 0...maxRedirects {
        let isTrustedHop = trustedOrigin.map { isSameOrigin(currentUrl, $0) } ?? false
        if !isTrustedHop {
            try validateDownloadUrl(currentUrl)
            if fetch == nil {
                try await validateResolvedDownloadHost(currentUrl)
            }
        }

        guard let requestURL = URL(string: currentUrl) else {
            throw DownloadError(url: url, message: "Invalid URL: \(currentUrl)")
        }

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = PROVIDER_UTILS_DEFAULT_REQUEST_TIMEOUT_INTERVAL
        request.fetchRedirectMode = .manual

        if let currentHeaders {
            for (name, value) in currentHeaders {
                request.setValue(value, forHTTPHeaderField: name)
            }
        }

        let response = try await fetchHop(request, url: url, fetch: fetchImpl, isAborted: isAborted)

        if redirectStatusCodes.contains(response.statusCode),
           let location = response.httpResponse.value(forHTTPHeaderField: "Location"),
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

/// Sends one hop and fails closed when the fetch function followed a redirect itself.
private func fetchHop(
    _ request: URLRequest,
    url: String,
    fetch: @escaping FetchFunction,
    isAborted: (@Sendable () -> Bool)?
) async throws -> ProviderHTTPResponse {
    // `request.url` is always set by the callers.
    let requestURL = request.url!

    let fetchResponse = try await fetchWithAbortCheck(
        fetch: fetch,
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

    if let responseURL = httpResponse.url, !isSameRequestTarget(responseURL, requestURL) {
        startCancellingResponseBody(response)
        throw DownloadError(
            url: url,
            message: "Redirect from \(requestURL.absoluteString) could not be validated and was blocked"
        )
    }

    return response
}

/// Compares scheme, host, port, path and query; an empty path equals `/`.
private func isSameRequestTarget(_ lhs: URL, _ rhs: URL) -> Bool {
    guard let left = URLComponents(url: lhs, resolvingAgainstBaseURL: true),
          let right = URLComponents(url: rhs, resolvingAgainstBaseURL: true) else {
        return lhs.absoluteString == rhs.absoluteString
    }

    func port(_ components: URLComponents) -> Int? {
        switch (components.scheme?.lowercased(), components.port) {
        case ("http", 80), ("https", 443):
            return nil
        default:
            return components.port
        }
    }

    return left.scheme?.lowercased() == right.scheme?.lowercased()
        && left.host?.lowercased() == right.host?.lowercased()
        && port(left) == port(right)
        && (left.percentEncodedPath.isEmpty ? "/" : left.percentEncodedPath)
            == (right.percentEncodedPath.isEmpty ? "/" : right.percentEncodedPath)
        && left.percentEncodedQuery == right.percentEncodedQuery
}

private func startCancellingResponseBody(_ response: ProviderHTTPResponse) {
    Task {
        await cancelResponseBody(response)
    }
}

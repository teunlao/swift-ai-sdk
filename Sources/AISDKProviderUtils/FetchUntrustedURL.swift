import Foundation

// Providers can use arbitrary credential header names. Only established
// non-credential request metadata is safe to forward without an origin assertion.
private let safeUntrustedFirstHopHeaders: Set<String> = [
    "accept",
    "accept-language",
    "baggage",
    "cache-control",
    "idempotency-key",
    "if-match",
    "if-modified-since",
    "if-none-match",
    "if-range",
    "if-unmodified-since",
    "pragma",
    "range",
    "traceparent",
    "tracestate",
    "user-agent",
    "x-correlation-id",
    "x-request-id",
]

/**
 Fetches an untrusted URL with first-hop credential isolation and validated redirects.

 Without a matching `credentialedOrigin` (or `trustedOrigin` when it is `nil`),
 only allowlisted request metadata is sent on the first hop: vendor credential
 header names cannot be inferred safely. Proxy, metadata, cookie and hop-by-hop
 headers are removed even for a matching origin. Redirect handling, URL
 validation and cross-origin header stripping are those of
 `fetchWithValidatedRedirects`.

 Both origin options come from developer configuration, never from response data.

 Hostname checks are not pinned to the connection, so there is no guarantee
 against DNS rebinding; constrain egress at the network layer for untrusted URLs.

 Swift port of `@ai-sdk/provider-utils/src/fetch-untrusted-url.ts`.

 - Parameters:
   - credentialedOrigin: Origin allowed to receive arbitrary caller headers on the
     first hop. Defaults to `trustedOrigin`; an explicit value takes precedence and
     does not exempt the URL from validation.
   - untrustedFirstHopHeaders: Additional header names (case-insensitive) safe to
     disclose to an untrusted first hop. Only non-credential protocol metadata.
 */
public func fetchUntrustedUrl(
    url: String,
    headers: [String: String]? = nil,
    isAborted: (@Sendable () -> Bool)? = nil,
    maxRedirects: Int = 10,
    fetch: FetchFunction? = nil,
    trustedOrigin: String? = nil,
    credentialedOrigin: String? = nil,
    untrustedFirstHopHeaders: [String]? = nil
) async throws -> ProviderHTTPResponse {
    var firstHopHeaders: [String: String]?

    if let headers {
        let sanitized = sanitizeRequestHeaders(headers)
        let origin = credentialedOrigin ?? trustedOrigin

        if let origin, isSameOrigin(url, origin) {
            firstHopHeaders = sanitized
        } else {
            let allowedHeaders = safeUntrustedFirstHopHeaders
                .union((untrustedFirstHopHeaders ?? []).map { $0.lowercased() })
            firstHopHeaders = sanitized.filter { allowedHeaders.contains($0.key) }
        }
    }

    return try await fetchWithValidatedRedirects(
        url: url,
        headers: firstHopHeaders,
        isAborted: isAborted,
        maxRedirects: maxRedirects,
        fetch: fetch,
        trustedOrigin: trustedOrigin
    )
}

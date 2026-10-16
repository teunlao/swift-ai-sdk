import Foundation

/**
 Request headers stripped before fetching an untrusted URL: host routing,
 proxy/origin spoofing, cloud metadata, cookies and hop-by-hop transport headers.

 Credential headers such as `Authorization` are not listed: trusted provider
 requests may need them. `fetchUntrustedUrl` restricts an untrusted first hop to
 an allowlist instead, and redirects that cross origin drop every caller header
 except `user-agent`.
 */
private let blockedRequestHeaders: Set<String> = [
    // Hop-by-hop / transport (RFC 7230 §6.1)
    "connection",
    "keep-alive",
    "te",
    "trailer",
    "transfer-encoding",
    "upgrade",

    // Host / virtual-host routing
    "host",

    // Proxy / origin spoofing
    "forwarded",
    "proxy-authorization",
    "via",
    "x-forwarded-for",
    "x-forwarded-host",
    "x-forwarded-proto",
    "x-real-ip",

    // Cloud metadata (GCP, AWS IMDSv1/v2, Azure, Alibaba, DigitalOcean)
    "metadata",
    "metadata-flavor",
    "x-aws-ec2-metadata-token",
    "x-metadata-token",

    // Session / cookie
    "cookie",
    "set-cookie",
]

/**
 Returns `headers` with blocked request headers removed. Names are compared
 case-insensitively and returned lowercased, as a fetch `Headers` object does.

 Port of `@ai-sdk/provider-utils/src/sanitize-request-headers.ts`.
 */
public func sanitizeRequestHeaders(_ headers: [String: String]) -> [String: String] {
    var sanitized: [String: String] = [:]
    for (name, value) in headers {
        let lowercased = name.lowercased()
        if !blockedRequestHeaders.contains(lowercased) {
            sanitized[lowercased] = value
        }
    }
    return sanitized
}

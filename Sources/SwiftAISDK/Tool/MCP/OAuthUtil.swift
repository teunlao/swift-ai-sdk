import Foundation

/**
 Utilities for handling OAuth resource URIs.

 Port of `packages/mcp/src/util/oauth-util.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
 */

/// Converts a server URL to a resource URL by removing the fragment.
/// RFC 8707 section 2: resource URIs MUST NOT include a fragment.
public func resourceUrlFromServerUrl(_ url: URL) -> URL {
    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
        return url
    }

    components.fragment = nil

    if let scheme = components.scheme?.lowercased() {
        components.scheme = scheme

        // Match JavaScript URL normalization: omit explicit default ports.
        if let port = components.port, isDefaultPort(port, forScheme: scheme) {
            components.port = nil
        }
    }

    if let host = components.host {
        components.host = host.lowercased()
    }

    // Match JavaScript URL.pathname, which is "/" for origin URLs without an explicit path.
    if components.host != nil, components.path.isEmpty {
        components.path = "/"
    }

    return components.url ?? url
}

private func isDefaultPort(_ port: Int, forScheme scheme: String) -> Bool {
    switch scheme.lowercased() {
    case "http":
        return port == 80
    case "https":
        return port == 443
    default:
        return false
    }
}

/// Serializes origin-only resources without the trailing slash added by URL normalization.
public func resourceUrlStripSlash(_ resource: URL) -> String {
    var components = URLComponents(url: resourceUrlFromServerUrl(resource), resolvingAgainstBaseURL: false)
    components?.percentEncodedFragment = URLComponents(url: resource, resolvingAgainstBaseURL: false)?.percentEncodedFragment
    let normalized = components?.url ?? resource
    let href = normalized.absoluteString
    if normalizePathname(normalized) == "/", href.hasSuffix("/") {
        return String(href.dropLast())
    }
    return href
}

/// Checks if a requested resource URL matches a configured resource URL.
///
/// A requested resource matches if it has the same scheme, domain, port,
/// and its path starts with the configured resource's path.
public func checkResourceAllowed(requestedResource: URL, configuredResource: URL) -> Bool {
    guard let requestedOrigin = normalizedOriginComponents(requestedResource),
          let configuredOrigin = normalizedOriginComponents(configuredResource)
    else {
        return false
    }

    if requestedOrigin != configuredOrigin {
        return false
    }

    let requestedPathname = normalizePathname(requestedResource)
    let configuredPathname = normalizePathname(configuredResource)

    // Handle cases like requested=/foo and configured=/foo/
    if requestedPathname.count < configuredPathname.count {
        return false
    }

    func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : "\(path)/"
    }

    let requestedPath = ensureTrailingSlash(requestedPathname)
    let configuredPath = ensureTrailingSlash(configuredPathname)

    return requestedPath.hasPrefix(configuredPath)
}

private func normalizePathname(_ url: URL) -> String {
    // JavaScript's pathname preserves percent escapes and trailing slashes.
    let pathname: String = {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.path
        }
        return components.percentEncodedPath
    }()

    return pathname.isEmpty ? "/" : pathname
}

private func normalizedOriginComponents(_ url: URL) -> (scheme: String, host: String, port: Int?)? {
    guard let scheme = url.scheme?.lowercased(),
          let host = url.host?.lowercased()
    else {
        return nil
    }

    let port: Int? = {
        guard let port = url.port else { return nil }
        return isDefaultPort(port, forScheme: scheme) ? nil : port
    }()

    return (scheme: scheme, host: host, port: port)
}

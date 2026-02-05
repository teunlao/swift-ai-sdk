import Foundation

/**
 Utilities for handling OAuth resource URIs.

 Port of `packages/mcp/src/util/oauth-util.ts`.
 Upstream commit: f3a72bc2a
 */

/// Converts a server URL to a resource URL by removing the fragment.
/// RFC 8707 section 2: resource URIs MUST NOT include a fragment.
public func resourceUrlFromServerUrl(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.fragment = nil
    return components?.url ?? url
}

/// Checks if a requested resource URL matches a configured resource URL.
///
/// A requested resource matches if it has the same scheme, domain, port,
/// and its path starts with the configured resource's path.
public func checkResourceAllowed(requestedResource: URL, configuredResource: URL) -> Bool {
    if requestedResource.scheme?.lowercased() != configuredResource.scheme?.lowercased() {
        return false
    }

    if requestedResource.host?.lowercased() != configuredResource.host?.lowercased() {
        return false
    }

    if requestedResource.port != configuredResource.port {
        return false
    }

    // Handle cases like requested=/foo and configured=/foo/
    if requestedResource.path.count < configuredResource.path.count {
        return false
    }

    func ensureTrailingSlash(_ path: String) -> String {
        path.hasSuffix("/") ? path : "\(path)/"
    }

    let requestedPath = ensureTrailingSlash(requestedResource.path)
    let configuredPath = ensureTrailingSlash(configuredResource.path)

    return requestedPath.hasPrefix(configuredPath)
}


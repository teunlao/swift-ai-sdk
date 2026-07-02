import Foundation

/**
 Returns true when two absolute URLs have the same scheme, host, and effective port.

 Swift port of `@ai-sdk/provider-utils/src/is-same-origin.ts`.
 */
public func isSameOrigin(_ url: String, _ baseURL: String) -> Bool {
    guard
        let origin = urlOriginComponents(url),
        let baseOrigin = urlOriginComponents(baseURL)
    else {
        return false
    }

    return origin == baseOrigin
}

private struct URLOriginComponents: Equatable {
    let scheme: String
    let host: String
    let port: Int?
}

private func urlOriginComponents(_ url: String) -> URLOriginComponents? {
    guard
        let components = URLComponents(string: url),
        let scheme = components.scheme?.lowercased(),
        let host = components.host?.lowercased()
    else {
        return nil
    }

    return URLOriginComponents(
        scheme: scheme,
        host: host,
        port: normalizedPort(components.port, scheme: scheme)
    )
}

private func normalizedPort(_ port: Int?, scheme: String) -> Int? {
    switch (scheme, port) {
    case ("http", 80), ("https", 443):
        return nil
    default:
        return port
    }
}

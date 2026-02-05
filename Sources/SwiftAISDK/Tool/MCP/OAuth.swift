import Foundation
import CryptoKit
import Security

/**
 OAuth support for MCP transports.

 Port of `packages/mcp/src/tool/oauth.ts`.
 Upstream commit: f3a72bc2a
 */

public enum AuthResult: String, Sendable {
    case authorized = "AUTHORIZED"
    case redirect = "REDIRECT"
}

public enum OAuthCredentialInvalidationScope: String, Sendable {
    case all
    case client
    case tokens
    case verifier
}

public typealias OAuthAddClientAuthentication = @Sendable (
    _ headers: inout [String: String],
    _ params: inout [String: String],
    _ authorizationServerUrl: URL,
    _ metadata: AuthorizationServerMetadata?
) async throws -> Void

public typealias OAuthInvalidateCredentials = @Sendable (
    _ scope: OAuthCredentialInvalidationScope
) async throws -> Void

public typealias OAuthSaveClientInformation = @Sendable (
    _ clientInformation: OAuthClientInformation
) async throws -> Void

public typealias OAuthStateProvider = @Sendable () async throws -> String

public typealias OAuthValidateResourceURL = @Sendable (
    _ serverUrl: URL,
    _ resource: String?
) async throws -> URL?

public protocol OAuthClientProvider: Sendable {
    /// Returns current access token if present; nil otherwise.
    func tokens() async throws -> OAuthTokens?

    func saveTokens(_ tokens: OAuthTokens) async throws

    func redirectToAuthorization(_ authorizationUrl: URL) async throws

    func saveCodeVerifier(_ codeVerifier: String) async throws

    func codeVerifier() async throws -> String

    /// Adds custom client authentication to OAuth token requests.
    ///
    /// When provided, this overrides the default OAuth 2.1 authentication selection logic.
    var addClientAuthentication: OAuthAddClientAuthentication? { get }

    /// Provides a way for the client to invalidate stored credentials if the server indicates they are no longer valid.
    var invalidateCredentials: OAuthInvalidateCredentials? { get }

    var redirectUrl: URL { get }

    var clientMetadata: OAuthClientMetadata { get }

    func clientInformation() async throws -> OAuthClientInformation?

    var saveClientInformation: OAuthSaveClientInformation? { get }

    var state: OAuthStateProvider? { get }

    var validateResourceURL: OAuthValidateResourceURL? { get }
}

public extension OAuthClientProvider {
    var addClientAuthentication: OAuthAddClientAuthentication? { nil }
    var invalidateCredentials: OAuthInvalidateCredentials? { nil }
    var saveClientInformation: OAuthSaveClientInformation? { nil }
    var state: OAuthStateProvider? { nil }
    var validateResourceURL: OAuthValidateResourceURL? { nil }
}

public struct UnauthorizedError: Error, LocalizedError, Sendable {
    public let message: String

    public init(message: String = "Unauthorized") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

/// Extracts the OAuth 2.0 Protected Resource Metadata URL from a WWW-Authenticate header (RFC9728).
/// Looks for a `resource_metadata="..."` parameter.
public func extractResourceMetadataUrl(_ response: HTTPURLResponse) -> URL? {
    let headerValue: String? = {
        for (keyAny, valueAny) in response.allHeaderFields {
            guard let key = keyAny as? String else { continue }
            if key.lowercased() == "www-authenticate" {
                return valueAny as? String
            }
        }
        return nil
    }()

    guard let header = headerValue else { return nil }

    let parts = header.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
    guard parts.count == 2 else { return nil }

    let type = parts[0].lowercased()
    guard type == "bearer" else { return nil }

    // regex taken from MCP spec
    let pattern = "resource_metadata=\\\"([^\\\"]*)\\\""
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
    let range = NSRange(header.startIndex..<header.endIndex, in: header)
    guard let match = regex.firstMatch(in: header, range: range),
          match.numberOfRanges >= 2,
          let urlRange = Range(match.range(at: 1), in: header)
    else { return nil }

    let urlString = String(header[urlRange])
    return URL(string: urlString)
}

// MARK: - Network Helpers

public typealias MCPFetchFunction = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

private func defaultFetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
    let (data, response) = try await URLSession.shared.data(for: request)
    guard let http = response as? HTTPURLResponse else {
        throw MCPClientError(message: "OAuth fetch failed: invalid response type")
    }
    return (data, http)
}

private func fetchWithCorsRetry(
    url: URL,
    headers: [String: String]?,
    fetchFn: MCPFetchFunction
) async throws -> (Data, HTTPURLResponse)? {
    do {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        headers?.forEach { request.setValue($1, forHTTPHeaderField: $0) }
        let (data, response) = try await fetchFn(request)
        return (data, response)
    } catch let error as URLError {
        if headers != nil {
            return try await fetchWithCorsRetry(url: url, headers: nil, fetchFn: fetchFn)
        }
        _ = error
        return nil
    }
}

private func tryMetadataDiscovery(
    url: URL,
    protocolVersion: String,
    fetchFn: MCPFetchFunction
) async throws -> (Data, HTTPURLResponse)? {
    let headers = [
        "MCP-Protocol-Version": protocolVersion,
    ]
    return try await fetchWithCorsRetry(url: url, headers: headers, fetchFn: fetchFn)
}

private func shouldAttemptFallback(response: HTTPURLResponse?, pathname: String) -> Bool {
    guard let response else { return true }
    return response.statusCode >= 400 && response.statusCode < 500 && pathname != "/"
}

private func buildWellKnownPath(
    _ wellKnownPrefix: String,
    pathname: String = "",
    prependPathname: Bool = false
) -> String {
    var normalizedPathname = pathname
    if normalizedPathname.hasSuffix("/") {
        normalizedPathname = String(normalizedPathname.dropLast())
    }

    if prependPathname {
        return "\(normalizedPathname)/.well-known/\(wellKnownPrefix)"
    }

    return "/.well-known/\(wellKnownPrefix)\(normalizedPathname)"
}

private func discoverMetadataWithFallback(
    serverUrl: URL,
    wellKnownType: String,
    fetchFn: MCPFetchFunction,
    protocolVersion: String = LATEST_PROTOCOL_VERSION,
    metadataUrl: URL? = nil,
    metadataServerUrl: URL? = nil
) async throws -> (Data, HTTPURLResponse)? {
    let issuer = serverUrl

    let url: URL = {
        if let metadataUrl {
            return metadataUrl
        }

        let wellKnownPath = buildWellKnownPath(wellKnownType, pathname: issuer.path)
        let base = metadataServerUrl ?? issuer
        var resolved = URL(string: wellKnownPath, relativeTo: base)?.absoluteURL ?? base

        if let components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
            var updated = components
            updated.query = URLComponents(url: issuer, resolvingAgainstBaseURL: false)?.query
            resolved = updated.url ?? resolved
        }

        return resolved
    }()

    var response = try await tryMetadataDiscovery(url: url, protocolVersion: protocolVersion, fetchFn: fetchFn)

    if metadataUrl == nil && shouldAttemptFallback(response: response?.1, pathname: issuer.path) {
        let rootUrl = URL(string: "/.well-known/\(wellKnownType)", relativeTo: issuer)?.absoluteURL ?? issuer
        response = try await tryMetadataDiscovery(url: rootUrl, protocolVersion: protocolVersion, fetchFn: fetchFn)
    }

    return response
}

// MARK: - Discovery

public func discoverOAuthProtectedResourceMetadata(
    serverUrl: URL,
    protocolVersion: String = LATEST_PROTOCOL_VERSION,
    resourceMetadataUrl: URL? = nil,
    fetchFn: MCPFetchFunction? = nil
) async throws -> OAuthProtectedResourceMetadata {
    let fetchFn = fetchFn ?? defaultFetch
    let response = try await discoverMetadataWithFallback(
        serverUrl: serverUrl,
        wellKnownType: "oauth-protected-resource",
        fetchFn: fetchFn,
        protocolVersion: protocolVersion,
        metadataUrl: resourceMetadataUrl
    )

    if response == nil || response?.1.statusCode == 404 {
        throw MCPClientError(message: "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
    }

    guard let (data, http) = response else {
        throw MCPClientError(message: "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
    }

    guard (200...299).contains(http.statusCode) else {
        throw MCPClientError(
            message: "HTTP \(http.statusCode) trying to load well-known OAuth protected resource metadata."
        )
    }

    return try JSONDecoder().decode(OAuthProtectedResourceMetadata.self, from: data)
}

public enum AuthorizationServerDiscoveryType: Sendable {
    case oauth
    case oidc
}

public func buildDiscoveryUrls(authorizationServerUrl: URL) -> [(url: URL, type: AuthorizationServerDiscoveryType)] {
    let hasPath = authorizationServerUrl.path != "/"
    var urlsToTry: [(url: URL, type: AuthorizationServerDiscoveryType)] = []

    if !hasPath {
        urlsToTry.append((URL(string: "/.well-known/oauth-authorization-server", relativeTo: URL(string: authorizationServerUrl.origin)!)!.absoluteURL, .oauth))
        urlsToTry.append((URL(string: "/.well-known/openid-configuration", relativeTo: URL(string: authorizationServerUrl.origin)!)!.absoluteURL, .oidc))
        return urlsToTry
    }

    var pathname = authorizationServerUrl.path
    if pathname.hasSuffix("/") {
        pathname = String(pathname.dropLast())
    }

    let origin = URL(string: authorizationServerUrl.origin)!
    urlsToTry.append((URL(string: "/.well-known/oauth-authorization-server\(pathname)", relativeTo: origin)!.absoluteURL, .oauth))
    urlsToTry.append((URL(string: "/.well-known/oauth-authorization-server", relativeTo: origin)!.absoluteURL, .oauth))
    urlsToTry.append((URL(string: "/.well-known/openid-configuration\(pathname)", relativeTo: origin)!.absoluteURL, .oidc))
    urlsToTry.append((URL(string: "\(pathname)/.well-known/openid-configuration", relativeTo: origin)!.absoluteURL, .oidc))

    return urlsToTry
}

public func discoverAuthorizationServerMetadata(
    authorizationServerUrl: URL,
    protocolVersion: String = LATEST_PROTOCOL_VERSION,
    fetchFn: MCPFetchFunction? = nil
) async throws -> AuthorizationServerMetadata? {
    let fetchFn = fetchFn ?? defaultFetch
    let headers = ["MCP-Protocol-Version": protocolVersion]

    for (endpointUrl, type) in buildDiscoveryUrls(authorizationServerUrl: authorizationServerUrl) {
        let response = try await fetchWithCorsRetry(url: endpointUrl, headers: headers, fetchFn: fetchFn)

        guard let (data, http) = response else {
            continue
        }

        if !(200...299).contains(http.statusCode) {
            if http.statusCode >= 400 && http.statusCode < 500 {
                continue
            }

            throw MCPClientError(
                message: "HTTP \(http.statusCode) trying to load \(type == .oauth ? "OAuth" : "OpenID provider") metadata from \(endpointUrl)"
            )
        }

        let metadata = try JSONDecoder().decode(AuthorizationServerMetadata.self, from: data)

        if type == .oidc && metadata.codeChallengeMethodsSupported?.contains("S256") != true {
            throw MCPClientError(
                message: "Incompatible OIDC provider at \(endpointUrl): does not support S256 code challenge method required by MCP specification"
            )
        }

        return metadata
    }

    return nil
}

// MARK: - Authorization

private func base64URLEncode(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func pkceChallenge() -> (codeVerifier: String, codeChallenge: String) {
    var bytes = [UInt8](repeating: 0, count: 32)
    _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
    let verifier = base64URLEncode(Data(bytes))

    let digest = SHA256.hash(data: Data(verifier.utf8))
    let challenge = base64URLEncode(Data(digest))

    return (verifier, challenge)
}

public func startAuthorization(
    authorizationServerUrl: URL,
    metadata: AuthorizationServerMetadata?,
    clientInformation: OAuthClientInformation,
    redirectUrl: URL,
    scope: String? = nil,
    state: String? = nil,
    resource: URL? = nil
) throws -> (authorizationUrl: URL, codeVerifier: String) {
    let responseType = "code"
    let codeChallengeMethod = "S256"

    let authorizationUrl: URL
    if let metadata {
        authorizationUrl = metadata.authorizationEndpoint.url

        if !metadata.responseTypesSupported.contains(responseType) {
            throw MCPClientError(message: "Incompatible auth server: does not support response type \(responseType)")
        }

        if metadata.codeChallengeMethodsSupported?.contains(codeChallengeMethod) != true {
            throw MCPClientError(
                message: "Incompatible auth server: does not support code challenge method \(codeChallengeMethod)"
            )
        }
    } else {
        authorizationUrl = URL(string: "/authorize", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl
    }

    let challenge = pkceChallenge()

    var components = URLComponents(url: authorizationUrl, resolvingAgainstBaseURL: false)
    var items = components?.queryItems ?? []

    items.append(URLQueryItem(name: "response_type", value: responseType))
    items.append(URLQueryItem(name: "client_id", value: clientInformation.clientId))
    items.append(URLQueryItem(name: "code_challenge", value: challenge.codeChallenge))
    items.append(URLQueryItem(name: "code_challenge_method", value: codeChallengeMethod))
    items.append(URLQueryItem(name: "redirect_uri", value: redirectUrl.absoluteString))

    if let state {
        items.append(URLQueryItem(name: "state", value: state))
    }

    if let scope {
        items.append(URLQueryItem(name: "scope", value: scope))
        if scope.contains("offline_access") {
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        }
    }

    if let resource {
        items.append(URLQueryItem(name: "resource", value: resource.absoluteString))
    }

    components?.queryItems = items
    return (components?.url ?? authorizationUrl, challenge.codeVerifier)
}

private enum ClientAuthMethod: String, Sendable {
    case clientSecretBasic = "client_secret_basic"
    case clientSecretPost = "client_secret_post"
    case none
}

private func selectClientAuthMethod(
    clientInformation: OAuthClientInformation,
    supportedMethods: [String]
) -> ClientAuthMethod {
    let hasClientSecret = clientInformation.clientSecret != nil

    if supportedMethods.isEmpty {
        return hasClientSecret ? .clientSecretPost : .none
    }

    if hasClientSecret && supportedMethods.contains(ClientAuthMethod.clientSecretBasic.rawValue) {
        return .clientSecretBasic
    }

    if hasClientSecret && supportedMethods.contains(ClientAuthMethod.clientSecretPost.rawValue) {
        return .clientSecretPost
    }

    if supportedMethods.contains(ClientAuthMethod.none.rawValue) {
        return .none
    }

    return hasClientSecret ? .clientSecretPost : .none
}

private func applyBasicAuth(clientId: String, clientSecret: String?, headers: inout [String: String]) throws {
    guard let clientSecret else {
        throw MCPClientError(message: "client_secret_basic authentication requires a client_secret")
    }

    let credentials = Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
    headers["Authorization"] = "Basic \(credentials)"
}

private func applyPostAuth(clientId: String, clientSecret: String?, params: inout [String: String]) {
    params["client_id"] = clientId
    if let clientSecret {
        params["client_secret"] = clientSecret
    }
}

private func applyPublicAuth(clientId: String, params: inout [String: String]) {
    params["client_id"] = clientId
}

private func applyClientAuthentication(
    method: ClientAuthMethod,
    clientInformation: OAuthClientInformation,
    headers: inout [String: String],
    params: inout [String: String]
) throws {
    switch method {
    case .clientSecretBasic:
        try applyBasicAuth(clientId: clientInformation.clientId, clientSecret: clientInformation.clientSecret, headers: &headers)
    case .clientSecretPost:
        applyPostAuth(clientId: clientInformation.clientId, clientSecret: clientInformation.clientSecret, params: &params)
    case .none:
        applyPublicAuth(clientId: clientInformation.clientId, params: &params)
    }
}

private struct ErrorURIError: Error, CustomStringConvertible, Sendable {
    let uri: String
    var description: String { uri }
}

public func parseErrorResponse(statusCode: Int?, body: String) -> any Error {
    do {
        let data = Data(body.utf8)
        let parsed = try JSONDecoder().decode(OAuthErrorResponse.self, from: data)
        let message = parsed.errorDescription ?? ""
        let cause = parsed.errorUri.map { ErrorURIError(uri: $0) }

        switch parsed.error {
        case ServerError.errorCode:
            return ServerError(message: message, cause: cause)
        case InvalidClientError.errorCode:
            return InvalidClientError(message: message, cause: cause)
        case InvalidGrantError.errorCode:
            return InvalidGrantError(message: message, cause: cause)
        case UnauthorizedClientError.errorCode:
            return UnauthorizedClientError(message: message, cause: cause)
        default:
            return ServerError(message: message, cause: cause)
        }
    } catch {
        let prefix = statusCode.map { "HTTP \($0): " } ?? ""
        let errorMessage = "\(prefix)Invalid OAuth error response: \(error). Raw body: \(body)"
        return ServerError(message: errorMessage, cause: nil)
    }
}

private func percentEncodeFormComponent(_ string: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=")
    return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
}

private func formURLEncodedBody(_ params: [String: String]) -> Data {
    let pairs = params.map { key, value in
        "\(percentEncodeFormComponent(key))=\(percentEncodeFormComponent(value))"
    }
    return Data(pairs.sorted().joined(separator: "&").utf8)
}

public func exchangeAuthorization(
    authorizationServerUrl: URL,
    metadata: AuthorizationServerMetadata?,
    clientInformation: OAuthClientInformation,
    authorizationCode: String,
    codeVerifier: String,
    redirectUri: URL,
    resource: URL? = nil,
    addClientAuthentication: OAuthAddClientAuthentication? = nil,
    fetchFn: MCPFetchFunction? = nil
) async throws -> OAuthTokens {
    let fetchFn = fetchFn ?? defaultFetch
    let grantType = "authorization_code"

    let tokenUrl = metadata?.tokenEndpoint.url ?? URL(string: "/token", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl

    if let grantTypes = metadata?.grantTypesSupported, !grantTypes.contains(grantType) {
        throw MCPClientError(message: "Incompatible auth server: does not support grant type \(grantType)")
    }

    var headers: [String: String] = [
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    ]
    var params: [String: String] = [
        "grant_type": grantType,
        "code": authorizationCode,
        "code_verifier": codeVerifier,
        "redirect_uri": redirectUri.absoluteString,
    ]

    if let addClientAuthentication {
        try await addClientAuthentication(&headers, &params, authorizationServerUrl, metadata)
    } else {
        let supportedMethods = metadata?.tokenEndpointAuthMethodsSupported ?? []
        let authMethod = selectClientAuthMethod(clientInformation: clientInformation, supportedMethods: supportedMethods)
        try applyClientAuthentication(method: authMethod, clientInformation: clientInformation, headers: &headers, params: &params)
    }

    if let resource {
        params["resource"] = resource.absoluteString
    }

    var request = URLRequest(url: tokenUrl)
    request.httpMethod = "POST"
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    request.httpBody = formURLEncodedBody(params)

    let (data, http) = try await fetchFn(request)
    guard (200...299).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw parseErrorResponse(statusCode: http.statusCode, body: body)
    }

    return try JSONDecoder().decode(OAuthTokens.self, from: data)
}

public func refreshAuthorization(
    authorizationServerUrl: URL,
    metadata: AuthorizationServerMetadata?,
    clientInformation: OAuthClientInformation,
    refreshToken: String,
    resource: URL? = nil,
    addClientAuthentication: OAuthAddClientAuthentication? = nil,
    fetchFn: MCPFetchFunction? = nil
) async throws -> OAuthTokens {
    let fetchFn = fetchFn ?? defaultFetch
    let grantType = "refresh_token"

    let tokenUrl = metadata?.tokenEndpoint.url ?? URL(string: "/token", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl

    if let grantTypes = metadata?.grantTypesSupported, !grantTypes.contains(grantType) {
        throw MCPClientError(message: "Incompatible auth server: does not support grant type \(grantType)")
    }

    var headers: [String: String] = [
        "Content-Type": "application/x-www-form-urlencoded",
        "Accept": "application/json",
    ]
    var params: [String: String] = [
        "grant_type": grantType,
        "refresh_token": refreshToken,
    ]

    if let addClientAuthentication {
        try await addClientAuthentication(&headers, &params, authorizationServerUrl, metadata)
    } else {
        let supportedMethods = metadata?.tokenEndpointAuthMethodsSupported ?? []
        let authMethod = selectClientAuthMethod(clientInformation: clientInformation, supportedMethods: supportedMethods)
        try applyClientAuthentication(method: authMethod, clientInformation: clientInformation, headers: &headers, params: &params)
    }

    if let resource {
        params["resource"] = resource.absoluteString
    }

    var request = URLRequest(url: tokenUrl)
    request.httpMethod = "POST"
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    request.httpBody = formURLEncodedBody(params)

    let (data, http) = try await fetchFn(request)
    guard (200...299).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw parseErrorResponse(statusCode: http.statusCode, body: body)
    }

    var decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)
    if decoded.refreshToken == nil {
        decoded = OAuthTokens(
            accessToken: decoded.accessToken,
            idToken: decoded.idToken,
            tokenType: decoded.tokenType,
            expiresIn: decoded.expiresIn,
            scope: decoded.scope,
            refreshToken: refreshToken
        )
    }
    return decoded
}

public func registerClient(
    authorizationServerUrl: URL,
    metadata: AuthorizationServerMetadata?,
    clientMetadata: OAuthClientMetadata,
    fetchFn: MCPFetchFunction? = nil
) async throws -> OAuthClientInformationFull {
    let fetchFn = fetchFn ?? defaultFetch

    let registrationUrl: URL
    if let endpoint = metadata?.registrationEndpoint?.url {
        registrationUrl = endpoint
    } else if metadata != nil {
        throw MCPClientError(message: "Incompatible auth server: does not support dynamic client registration")
    } else {
        registrationUrl = URL(string: "/register", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl
    }

    var request = URLRequest(url: registrationUrl)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(clientMetadata)

    let (data, http) = try await fetchFn(request)
    guard (200...299).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw parseErrorResponse(statusCode: http.statusCode, body: body)
    }

    return try JSONDecoder().decode(OAuthClientInformationFull.self, from: data)
}

// MARK: - auth()

public func auth(
    _ provider: any OAuthClientProvider,
    serverUrl: URL,
    authorizationCode: String? = nil,
    scope: String? = nil,
    resourceMetadataUrl: URL? = nil,
    fetchFn: MCPFetchFunction? = nil
) async throws -> AuthResult {
    do {
        return try await authInternal(
            provider,
            serverUrl: serverUrl,
            authorizationCode: authorizationCode,
            scope: scope,
            resourceMetadataUrl: resourceMetadataUrl,
            fetchFn: fetchFn
        )
    } catch {
        if error is InvalidClientError || error is UnauthorizedClientError {
            try await provider.invalidateCredentials?(.all)
            return try await authInternal(
                provider,
                serverUrl: serverUrl,
                authorizationCode: authorizationCode,
                scope: scope,
                resourceMetadataUrl: resourceMetadataUrl,
                fetchFn: fetchFn
            )
        }

        if error is InvalidGrantError {
            try await provider.invalidateCredentials?(.tokens)
            return try await authInternal(
                provider,
                serverUrl: serverUrl,
                authorizationCode: authorizationCode,
                scope: scope,
                resourceMetadataUrl: resourceMetadataUrl,
                fetchFn: fetchFn
            )
        }

        throw error
    }
}

public func selectResourceURL(
    serverUrl: URL,
    provider: any OAuthClientProvider,
    resourceMetadata: OAuthProtectedResourceMetadata?
) async throws -> URL? {
    let defaultResource = resourceUrlFromServerUrl(serverUrl)

    if let validate = provider.validateResourceURL {
        return try await validate(defaultResource, resourceMetadata?.resource.absoluteString)
    }

    guard let resourceMetadata else {
        return nil
    }

    if !checkResourceAllowed(requestedResource: defaultResource, configuredResource: resourceMetadata.resource) {
        throw MCPClientError(
            message: "Protected resource \(resourceMetadata.resource) does not match expected \(defaultResource) (or origin)"
        )
    }

    return resourceMetadata.resource
}

private func authInternal(
    _ provider: any OAuthClientProvider,
    serverUrl: URL,
    authorizationCode: String?,
    scope: String?,
    resourceMetadataUrl: URL?,
    fetchFn: MCPFetchFunction?
) async throws -> AuthResult {
    var resourceMetadata: OAuthProtectedResourceMetadata?
    var authorizationServerUrl: URL?

    do {
        resourceMetadata = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl,
            resourceMetadataUrl: resourceMetadataUrl,
            fetchFn: fetchFn
        )

        if let servers = resourceMetadata?.authorizationServers, !servers.isEmpty {
            authorizationServerUrl = servers[0].url
        }
    } catch {
        // ignore and fall back
    }

    if authorizationServerUrl == nil {
        authorizationServerUrl = serverUrl
    }

    let resource = try await selectResourceURL(serverUrl: serverUrl, provider: provider, resourceMetadata: resourceMetadata)

    let metadata = try await discoverAuthorizationServerMetadata(
        authorizationServerUrl: authorizationServerUrl!,
        fetchFn: fetchFn
    )

    var clientInformation = try await provider.clientInformation()

    if clientInformation == nil {
        if authorizationCode != nil {
            throw MCPClientError(
                message: "Existing OAuth client information is required when exchanging an authorization code"
            )
        }

        guard let saveClientInformation = provider.saveClientInformation else {
            throw MCPClientError(
                message: "OAuth client information must be saveable for dynamic registration"
            )
        }

        let fullInformation = try await registerClient(
            authorizationServerUrl: authorizationServerUrl!,
            metadata: metadata,
            clientMetadata: provider.clientMetadata,
            fetchFn: fetchFn
        )

        let minimal = OAuthClientInformation(
            clientId: fullInformation.clientId,
            clientSecret: fullInformation.clientSecret,
            clientIdIssuedAt: fullInformation.clientIdIssuedAt,
            clientSecretExpiresAt: fullInformation.clientSecretExpiresAt
        )

        try await saveClientInformation(minimal)
        clientInformation = minimal
    }

    if let authorizationCode {
        let verifier = try await provider.codeVerifier()
        let tokens = try await exchangeAuthorization(
            authorizationServerUrl: authorizationServerUrl!,
            metadata: metadata,
            clientInformation: clientInformation!,
            authorizationCode: authorizationCode,
            codeVerifier: verifier,
            redirectUri: provider.redirectUrl,
            resource: resource,
            addClientAuthentication: provider.addClientAuthentication,
            fetchFn: fetchFn
        )

        try await provider.saveTokens(tokens)
        return .authorized
    }

    let tokens = try await provider.tokens()

    if let refreshToken = tokens?.refreshToken {
        do {
            let newTokens = try await refreshAuthorization(
                authorizationServerUrl: authorizationServerUrl!,
                metadata: metadata,
                clientInformation: clientInformation!,
                refreshToken: refreshToken,
                resource: resource,
                addClientAuthentication: provider.addClientAuthentication,
                fetchFn: fetchFn
            )

            try await provider.saveTokens(newTokens)
            return .authorized
        } catch {
            if !MCPClientOAuthError.isInstance(error) || error is ServerError {
                // Could not refresh OAuth tokens - continue to interactive authorization
            } else {
                throw error
            }
        }
    }

    let state = try await provider.state?()

    let authorization = try startAuthorization(
        authorizationServerUrl: authorizationServerUrl!,
        metadata: metadata,
        clientInformation: clientInformation!,
        redirectUrl: provider.redirectUrl,
        scope: scope ?? provider.clientMetadata.scope,
        state: state,
        resource: resource
    )

    try await provider.saveCodeVerifier(authorization.codeVerifier)
    try await provider.redirectToAuthorization(authorization.authorizationUrl)
    return .redirect
}

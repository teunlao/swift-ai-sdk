import Foundation
import CryptoKit
import Security
import AISDKProviderUtils

/**
 OAuth support for MCP transports.

 Port of `packages/mcp/src/tool/oauth.ts`.
 Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
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

public struct OAuthCredentialInvalidationContext: Sendable {
    public let tokens: OAuthTokens

    public init(tokens: OAuthTokens) {
        self.tokens = tokens
    }
}

public typealias OAuthInvalidateCredentials = @Sendable (
    _ scope: OAuthCredentialInvalidationScope,
    _ context: OAuthCredentialInvalidationContext?
) async throws -> Void

public struct OAuthAuthorizationServerInformation: Codable, Sendable, Equatable {
    public let issuer: String?
    public let authorizationServerUrl: URL
    public let tokenEndpoint: URL

    public init(issuer: String? = nil, authorizationServerUrl: URL, tokenEndpoint: URL) {
        self.issuer = issuer
        self.authorizationServerUrl = authorizationServerUrl
        self.tokenEndpoint = tokenEndpoint
    }
}

public typealias OAuthSaveAuthorizationServerInformation = @Sendable (OAuthAuthorizationServerInformation) async throws -> Void
public typealias OAuthValidateAuthorizationServerURL = @Sendable (URL, URL) async throws -> Void
public typealias OAuthSaveState = @Sendable (String) async throws -> Void
public typealias OAuthStoredState = @Sendable () async throws -> String?

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

    /// Shared stores must atomically compare the supplied token generation before deleting it.
    var invalidateCredentials: OAuthInvalidateCredentials? { get }

    var redirectUrl: URL { get }

    var clientMetadata: OAuthClientMetadata { get }

    func clientInformation() async throws -> OAuthClientInformation?

    var saveClientInformation: OAuthSaveClientInformation? { get }

    func isClientInformationDynamicallyRegistered() async throws -> Bool

    func authorizationServerInformation() async throws -> OAuthAuthorizationServerInformation?

    var saveAuthorizationServerInformation: OAuthSaveAuthorizationServerInformation? { get }

    var validateAuthorizationServerURL: OAuthValidateAuthorizationServerURL? { get }

    var state: OAuthStateProvider? { get }

    var saveState: OAuthSaveState? { get }

    var storedState: OAuthStoredState? { get }

    var validateResourceURL: OAuthValidateResourceURL? { get }
}

public extension OAuthClientProvider {
    var addClientAuthentication: OAuthAddClientAuthentication? { nil }
    var invalidateCredentials: OAuthInvalidateCredentials? { nil }
    var saveClientInformation: OAuthSaveClientInformation? { nil }
    func isClientInformationDynamicallyRegistered() async throws -> Bool { false }
    func authorizationServerInformation() async throws -> OAuthAuthorizationServerInformation? { nil }
    var saveAuthorizationServerInformation: OAuthSaveAuthorizationServerInformation? { nil }
    var validateAuthorizationServerURL: OAuthValidateAuthorizationServerURL? { nil }
    var state: OAuthStateProvider? { nil }
    var saveState: OAuthSaveState? { nil }
    var storedState: OAuthStoredState? { nil }
    var validateResourceURL: OAuthValidateResourceURL? { nil }
}

public struct UnauthorizedError: Error, LocalizedError, Sendable {
    public let message: String

    public init(message: String = "Unauthorized") {
        self.message = message
    }

    public var errorDescription: String? { message }
}

public func extractWWWAuthenticateParams(
    _ response: HTTPURLResponse
) -> (resourceMetadataUrl: URL?, scope: String?) {
    guard let header = response.value(forHTTPHeaderField: "WWW-Authenticate") else { return (nil, nil) }
    let parts = header.split(separator: " ", maxSplits: 1)
    guard parts.count == 2, parts[0].lowercased() == "bearer" else { return (nil, nil) }

    func parameter(_ name: String) -> String? {
        let pattern = "(?:^|[,\\s])\(name)=\"([^\"]*)\""
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: header, range: NSRange(header.startIndex..., in: header)),
              let range = Range(match.range(at: 1), in: header) else { return nil }
        return String(header[range])
    }

    let url = parameter("resource_metadata").flatMap(URL.init(string:))
    return (url?.scheme == nil ? nil : url, parameter("scope"))
}

/// Extracts the OAuth protected resource metadata URL from a bearer challenge.
public func extractResourceMetadataUrl(_ response: HTTPURLResponse) -> URL? {
    extractWWWAuthenticateParams(response).resourceMetadataUrl
}

// MARK: - Network Helpers

/// An injected fetch must honor `URLRequest.fetchRedirectMode` before sending credentials.
public typealias MCPFetchFunction = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

private func providerFetch(_ fetch: MCPFetchFunction?) -> FetchFunction? {
    guard let fetch else { return nil }
    return { request in
        let (data, response) = try await fetch(request)
        return FetchResponse(body: .data(data), urlResponse: response)
    }
}

private func isOAuthLoopbackHost(_ hostname: String?) -> Bool {
    guard let hostname else { return false }
    var host = hostname.lowercased()
    while host.hasSuffix(".") { host.removeLast() }
    return host == "localhost" || host.hasSuffix(".localhost") || host == "127.0.0.1" || host == "[::1]" || host == "::1"
}

private func assertSafeOAuthEndpoint(_ url: URL, allowLoopback: Bool = false) throws {
    if allowLoopback, ["http", "https"].contains(url.scheme?.lowercased() ?? ""), isOAuthLoopbackHost(url.host) {
        return
    }
    do {
        try validateDownloadUrl(url.absoluteString)
    } catch {
        throw MCPClientOAuthError(message: "OAuth endpoint URL is not allowed: \(url.absoluteString)", cause: error)
    }
}

private func trustedLoopbackOrigin(_ url: URL) -> String? {
    isOAuthLoopbackHost(url.host) ? url.origin : nil
}

private func fetchOAuthCredentials(
    _ request: URLRequest,
    authorizationServerUrl: URL,
    fetchFn: MCPFetchFunction?
) async throws -> (Data, HTTPURLResponse) {
    let response = try await fetchWithValidatedEndpoint(
        request: request,
        fetch: providerFetch(fetchFn),
        trustedOrigin: trustedLoopbackOrigin(authorizationServerUrl)
    )
    return (try await response.body.collectData(), response.httpResponse)
}

private func fetchWithCorsRetry(
    url: URL,
    headers: [String: String]?,
    fetchFn: MCPFetchFunction?,
    trustedOrigin: String? = nil
) async throws -> (Data, HTTPURLResponse)? {
    do {
        let response = try await fetchUntrustedUrl(
            url: url.absoluteString,
            headers: headers,
            fetch: providerFetch(fetchFn),
            trustedOrigin: trustedOrigin,
            untrustedFirstHopHeaders: ["mcp-protocol-version"]
        )
        return (try await response.body.collectData(), response.httpResponse)
    } catch is URLError {
        if headers != nil {
            return try await fetchWithCorsRetry(url: url, headers: nil, fetchFn: fetchFn, trustedOrigin: trustedOrigin)
        }
        return nil
    }
}

private func tryMetadataDiscovery(
    url: URL,
    protocolVersion: String,
    fetchFn: MCPFetchFunction?,
    trustedOrigin: String? = nil
) async throws -> (Data, HTTPURLResponse)? {
    let headers = [
        "MCP-Protocol-Version": protocolVersion,
    ]
    return try await fetchWithCorsRetry(url: url, headers: headers, fetchFn: fetchFn, trustedOrigin: trustedOrigin)
}

private func shouldAttemptFallback(response: HTTPURLResponse?, pathname: String) -> Bool {
    guard let response else { return true }
    let normalizedPathname = pathname.isEmpty ? "/" : pathname
    return response.statusCode >= 400 && response.statusCode < 500 && normalizedPathname != "/"
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
    fetchFn: MCPFetchFunction?,
    protocolVersion: String = LATEST_PROTOCOL_VERSION,
    metadataUrl: URL? = nil,
    metadataServerUrl: URL? = nil
) async throws -> (Data, HTTPURLResponse)? {
    let issuer = serverUrl

    let url: URL = {
        if let metadataUrl {
            return metadataUrl
        }

        let pathname = URLComponents(url: issuer, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? issuer.path
        let wellKnownPath = buildWellKnownPath(wellKnownType, pathname: pathname)
        let base = metadataServerUrl ?? issuer
        var resolved = URL(string: wellKnownPath, relativeTo: base)?.absoluteURL ?? base

        if let components = URLComponents(url: resolved, resolvingAgainstBaseURL: false) {
            var updated = components
            updated.percentEncodedQuery = URLComponents(url: issuer, resolvingAgainstBaseURL: false)?.percentEncodedQuery
            resolved = updated.url ?? resolved
        }

        return resolved
    }()

    var response = try await tryMetadataDiscovery(url: url, protocolVersion: protocolVersion, fetchFn: fetchFn, trustedOrigin: serverUrl.origin)

    let pathname = URLComponents(url: issuer, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? issuer.path
    if metadataUrl == nil && shouldAttemptFallback(response: response?.1, pathname: pathname) {
        let rootUrl = URL(string: "/.well-known/\(wellKnownType)", relativeTo: issuer)?.absoluteURL ?? issuer
        response = try await tryMetadataDiscovery(url: rootUrl, protocolVersion: protocolVersion, fetchFn: fetchFn, trustedOrigin: serverUrl.origin)
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

public func buildDiscoveryUrls(
    authorizationServerUrl: URL
) -> [(url: URL, type: AuthorizationServerDiscoveryType, expectedIssuer: String)] {
    let origin = authorizationServerUrl.origin
    var pathname = URLComponents(url: authorizationServerUrl, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
    if pathname.hasSuffix("/") { pathname.removeLast() }

    func endpoint(_ path: String) -> URL {
        var components = URLComponents(string: origin)!
        // Assigning the path keeps a leading double slash on the approved origin.
        components.percentEncodedPath = path
        return components.url!
    }

    if pathname.isEmpty {
        return [
            (endpoint("/.well-known/oauth-authorization-server"), .oauth, origin),
            (endpoint("/.well-known/openid-configuration"), .oidc, origin),
        ]
    }

    let pathIssuer = origin + pathname
    return [
        (endpoint("/.well-known/oauth-authorization-server\(pathname)"), .oauth, pathIssuer),
        (endpoint("/.well-known/oauth-authorization-server"), .oauth, origin),
        (endpoint("/.well-known/openid-configuration\(pathname)"), .oidc, pathIssuer),
        (endpoint("\(pathname)/.well-known/openid-configuration"), .oidc, pathIssuer),
    ]
}

public func discoverAuthorizationServerMetadata(
    authorizationServerUrl: URL,
    protocolVersion: String = LATEST_PROTOCOL_VERSION,
    fetchFn: MCPFetchFunction? = nil,
    trustedOrigin: String? = nil
) async throws -> AuthorizationServerMetadata? {
    let headers = ["MCP-Protocol-Version": protocolVersion]
    let candidates = buildDiscoveryUrls(authorizationServerUrl: authorizationServerUrl)
    guard candidates.allSatisfy({ $0.url.origin == authorizationServerUrl.origin }) else {
        throw MCPClientOAuthError(message: "OAuth discovery URL changed authorization-server origin")
    }

    for (endpointUrl, type, expectedIssuer) in candidates {
        let response = try await fetchWithCorsRetry(url: endpointUrl, headers: headers, fetchFn: fetchFn, trustedOrigin: trustedOrigin)

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
        if type == .oidc, metadata.jwksUri == nil || metadata.subjectTypesSupported == nil || metadata.idTokenSigningAlgValuesSupported == nil {
            throw MCPClientError(message: "OpenID provider metadata must include jwks_uri, subject_types_supported, and id_token_signing_alg_values_supported")
        }
        let issuerMatches = metadata.issuer == expectedIssuer
            || (expectedIssuer == URL(string: expectedIssuer)?.origin && metadata.issuer == expectedIssuer + "/")
        guard issuerMatches else {
            throw MCPClientOAuthError(message: "OAuth authorization server metadata issuer \(metadata.issuer) does not match expected issuer \(expectedIssuer)")
        }

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

private func pkceChallenge() throws -> (codeVerifier: String, codeChallenge: String) {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
        throw MCPClientOAuthError(message: "Could not generate a secure PKCE verifier")
    }
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

    let challenge = try pkceChallenge()

    var components = URLComponents(url: authorizationUrl, resolvingAgainstBaseURL: false)
    if let query = components?.percentEncodedQuery {
        components?.percentEncodedQuery = query.replacingOccurrences(of: "+", with: "%20")
    }
    var items = (components?.queryItems ?? []).filter { !$0.name.isEmpty || $0.value != nil }

    func set(_ name: String, _ value: String) {
        items.removeAll { $0.name == name }
        items.append(URLQueryItem(name: name, value: value))
    }
    set("response_type", responseType)
    set("client_id", clientInformation.clientId)
    set("code_challenge", challenge.codeChallenge)
    set("code_challenge_method", codeChallengeMethod)
    set("redirect_uri", redirectUrl.absoluteString)

    if let state, !state.isEmpty {
        set("state", state)
    }

    if let scope, !scope.isEmpty {
        set("scope", scope)
        if scope.contains("offline_access") {
            items.append(URLQueryItem(name: "prompt", value: "consent"))
        }
    }

    if let resource {
        set("resource", resourceUrlStripSlash(resource))
    }

    components?.percentEncodedQuery = items.map {
        "\(percentEncodeFormComponent($0.name))=\(percentEncodeFormComponent($0.value ?? ""))"
    }.joined(separator: "&")
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
    guard let clientSecret, !clientSecret.isEmpty else {
        throw MCPClientError(message: "client_secret_basic authentication requires a client_secret")
    }

    let credentials = Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
    headers["Authorization"] = "Basic \(credentials)"
}

private func applyPostAuth(clientId: String, clientSecret: String?, params: inout [String: String]) {
    params["client_id"] = clientId
    if let clientSecret, !clientSecret.isEmpty {
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
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789*-._ ")
    return (string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string)
        .replacingOccurrences(of: " ", with: "+")
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
    let grantType = "authorization_code"

    let tokenUrl = metadata?.tokenEndpoint.url ?? URL(string: "/token", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl

    try assertSafeOAuthEndpoint(tokenUrl, allowLoopback: tokenUrl.origin == trustedLoopbackOrigin(authorizationServerUrl))

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
        params["resource"] = resourceUrlStripSlash(resource)
    }

    var request = URLRequest(url: tokenUrl)
    request.httpMethod = "POST"
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    request.httpBody = formURLEncodedBody(params)

    let (data, http) = try await fetchOAuthCredentials(request, authorizationServerUrl: authorizationServerUrl, fetchFn: fetchFn)
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
    let grantType = "refresh_token"

    let tokenUrl = metadata?.tokenEndpoint.url ?? URL(string: "/token", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl

    try assertSafeOAuthEndpoint(tokenUrl, allowLoopback: tokenUrl.origin == trustedLoopbackOrigin(authorizationServerUrl))

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
        params["resource"] = resourceUrlStripSlash(resource)
    }

    var request = URLRequest(url: tokenUrl)
    request.httpMethod = "POST"
    headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }
    request.httpBody = formURLEncodedBody(params)

    let (data, http) = try await fetchOAuthCredentials(request, authorizationServerUrl: authorizationServerUrl, fetchFn: fetchFn)
    guard (200...299).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw parseErrorResponse(statusCode: http.statusCode, body: body)
    }

    var decoded = try JSONDecoder().decode(OAuthTokens.self, from: data)
    if decoded.refreshToken == nil {
        decoded.refreshToken = refreshToken
    }
    return decoded
}

public func registerClient(
    authorizationServerUrl: URL,
    metadata: AuthorizationServerMetadata?,
    clientMetadata: OAuthClientMetadata,
    fetchFn: MCPFetchFunction? = nil
) async throws -> OAuthClientInformationFull {
    let registrationUrl: URL
    if let endpoint = metadata?.registrationEndpoint?.url {
        registrationUrl = endpoint
    } else if metadata != nil {
        throw MCPClientError(message: "Incompatible auth server: does not support dynamic client registration")
    } else {
        registrationUrl = URL(string: "/register", relativeTo: authorizationServerUrl)?.absoluteURL ?? authorizationServerUrl
    }

    try assertSafeOAuthEndpoint(registrationUrl, allowLoopback: registrationUrl.origin == trustedLoopbackOrigin(authorizationServerUrl))
    var registrationMetadata = clientMetadata
    if registrationMetadata.applicationType == nil {
        registrationMetadata.applicationType = clientMetadata.redirectUris.allSatisfy { redirect in
            let url = redirect.url
            return !["http", "https"].contains(url.scheme?.lowercased() ?? "") || isOAuthLoopbackHost(url.host)
        } ? .native : .web
    }

    var request = URLRequest(url: registrationUrl)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(registrationMetadata)

    let (data, http) = try await fetchOAuthCredentials(request, authorizationServerUrl: authorizationServerUrl, fetchFn: fetchFn)
    guard (200...299).contains(http.statusCode) else {
        let body = String(data: data, encoding: .utf8) ?? ""
        throw parseErrorResponse(statusCode: http.statusCode, body: body)
    }

    return try JSONDecoder().decode(OAuthClientInformationFull.self, from: data)
}

// MARK: - auth()

private func normalizedOAuthURL(_ url: URL) -> URL {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: true)!
    components.scheme = components.scheme?.lowercased()
    components.host = components.host?.lowercased()
    if (components.scheme == "https" && components.port == 443) || (components.scheme == "http" && components.port == 80) {
        components.port = nil
    }
    if components.host != nil, components.path.isEmpty { components.path = "/" }
    return components.url!
}

private func authorizationServerInformation(
    _ serverUrl: URL,
    metadata: AuthorizationServerMetadata?
) -> OAuthAuthorizationServerInformation {
    OAuthAuthorizationServerInformation(
        issuer: metadata?.issuer ?? serverUrl.absoluteString,
        authorizationServerUrl: normalizedOAuthURL(serverUrl),
        tokenEndpoint: normalizedOAuthURL(metadata?.tokenEndpoint.url ?? URL(string: "/token", relativeTo: serverUrl)!.absoluteURL)
    )
}

private func credentialsInformation(
    issuer: SafeURL?,
    authorizationServer: SafeURL?,
    tokenEndpoint: SafeURL?
) -> OAuthAuthorizationServerInformation? {
    guard let authorizationServer, let tokenEndpoint else { return nil }
    return OAuthAuthorizationServerInformation(
        issuer: issuer?.url.absoluteString,
        authorizationServerUrl: normalizedOAuthURL(authorizationServer.url),
        tokenEndpoint: normalizedOAuthURL(tokenEndpoint.url)
    )
}

private func storedAuthorizationServerInformation(
    provider: any OAuthClientProvider,
    clientInformation: OAuthClientInformation,
    tokens: OAuthTokens? = nil
) async throws -> OAuthAuthorizationServerInformation? {
    if let tokens, let stored = credentialsInformation(
        issuer: tokens.issuer, authorizationServer: tokens.authorizationServer, tokenEndpoint: tokens.tokenEndpoint
    ) { return stored }
    if let stored = try await provider.authorizationServerInformation() {
        return OAuthAuthorizationServerInformation(
            issuer: stored.issuer,
            authorizationServerUrl: normalizedOAuthURL(stored.authorizationServerUrl),
            tokenEndpoint: normalizedOAuthURL(stored.tokenEndpoint)
        )
    }
    return credentialsInformation(
        issuer: clientInformation.issuer,
        authorizationServer: clientInformation.authorizationServer,
        tokenEndpoint: clientInformation.tokenEndpoint
    )
}

private func assertAuthorizationServerMatches(
    _ stored: OAuthAuthorizationServerInformation,
    _ current: OAuthAuthorizationServerInformation
) throws {
    if (stored.issuer != nil && current.issuer != nil && stored.issuer != current.issuer)
        || stored.authorizationServerUrl != current.authorizationServerUrl
        || stored.tokenEndpoint != current.tokenEndpoint {
        throw AuthorizationServerMismatchError(
            message: "OAuth authorization server metadata does not match the metadata that issued the stored credentials"
        )
    }
}

private func pinClientInformation(
    _ client: OAuthClientInformation,
    to information: OAuthAuthorizationServerInformation
) throws -> OAuthClientInformation {
    var result = client
    result.issuer = try information.issuer.map { issuer in
        guard let url = URL(string: issuer) else { throw SafeURLValidationError.invalidURL(url: issuer) }
        return try SafeURL(url)
    }
    result.authorizationServer = try SafeURL(information.authorizationServerUrl)
    result.tokenEndpoint = try SafeURL(information.tokenEndpoint)
    return result
}

private func pinTokens(_ tokens: OAuthTokens, to information: OAuthAuthorizationServerInformation) throws -> OAuthTokens {
    var result = tokens
    result.issuer = try information.issuer.map { issuer in
        guard let url = URL(string: issuer) else { throw SafeURLValidationError.invalidURL(url: issuer) }
        return try SafeURL(url)
    }
    result.authorizationServer = try SafeURL(information.authorizationServerUrl)
    result.tokenEndpoint = try SafeURL(information.tokenEndpoint)
    return result
}

public func auth(
    _ provider: any OAuthClientProvider,
    serverUrl: URL,
    authorizationCode: String? = nil,
    callbackState: String? = nil,
    callbackIssuer: String? = nil,
    scope: String? = nil,
    resourceMetadataUrl: URL? = nil,
    fetchFn: MCPFetchFunction? = nil
) async throws -> AuthResult {
    var refreshAttempt: OAuthTokens?
    do {
        return try await authInternal(
            provider, serverUrl: serverUrl, authorizationCode: authorizationCode,
            callbackState: callbackState, callbackIssuer: callbackIssuer, scope: scope,
            resourceMetadataUrl: resourceMetadataUrl, fetchFn: fetchFn, refreshAttempt: &refreshAttempt
        )
    } catch {
        if error is InvalidClientError || error is UnauthorizedClientError {
            guard authorizationCode == nil, try await provider.isClientInformationDynamicallyRegistered() else { throw error }
            try await provider.invalidateCredentials?(.all, nil)
        } else if error is InvalidGrantError, let tokens = refreshAttempt {
            try await provider.invalidateCredentials?(.tokens, OAuthCredentialInvalidationContext(tokens: tokens))
        } else {
            throw error
        }
        var retryAttempt: OAuthTokens?
        return try await authInternal(
            provider, serverUrl: serverUrl, authorizationCode: authorizationCode,
            callbackState: callbackState, callbackIssuer: callbackIssuer, scope: scope,
            resourceMetadataUrl: resourceMetadataUrl, fetchFn: fetchFn, refreshAttempt: &retryAttempt
        )
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
    callbackState: String?,
    callbackIssuer: String?,
    scope: String?,
    resourceMetadataUrl: URL?,
    fetchFn: MCPFetchFunction?,
    refreshAttempt: inout OAuthTokens?
) async throws -> AuthResult {
    if let resourceMetadataUrl, resourceMetadataUrl.origin != serverUrl.origin {
        throw MCPClientOAuthError(
            message: "OAuth protected resource metadata URL \(resourceMetadataUrl) must have the same origin as the MCP server URL \(serverUrl.origin)"
        )
    }

    var resourceMetadata: OAuthProtectedResourceMetadata?
    var discoveredServerUrl: URL?
    do {
        resourceMetadata = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl, resourceMetadataUrl: resourceMetadataUrl, fetchFn: fetchFn
        )
        discoveredServerUrl = resourceMetadata?.authorizationServers?.first?.url
    } catch {
        // Missing protected resource metadata retains legacy MCP-as-AS discovery.
    }

    var clientInformation: OAuthClientInformation?
    var callbackInformation: OAuthAuthorizationServerInformation?
    if authorizationCode != nil {
        clientInformation = try await provider.clientInformation()
        if let clientInformation {
            callbackInformation = try await storedAuthorizationServerInformation(provider: provider, clientInformation: clientInformation)
        }
    }
    let authorizationServerUrl = discoveredServerUrl ?? callbackInformation?.authorizationServerUrl ?? serverUrl
    let trustedOrigin = authorizationServerUrl.origin == serverUrl.origin
        || (isOAuthLoopbackHost(serverUrl.host) && isOAuthLoopbackHost(authorizationServerUrl.host))
        ? authorizationServerUrl.origin : nil
    if trustedOrigin == nil { try assertSafeOAuthEndpoint(authorizationServerUrl) }

    let resource = try await selectResourceURL(serverUrl: serverUrl, provider: provider, resourceMetadata: resourceMetadata)
    try await provider.validateAuthorizationServerURL?(serverUrl, authorizationServerUrl)
    let metadata = try await discoverAuthorizationServerMetadata(
        authorizationServerUrl: authorizationServerUrl, fetchFn: fetchFn, trustedOrigin: trustedOrigin
    )
    let currentInformation = authorizationServerInformation(authorizationServerUrl, metadata: metadata)
    var clientMetadata = provider.clientMetadata
    let resourceScopes = resourceMetadata?.scopesSupported?.joined(separator: " ")
    let selectedScope = scope.flatMap { $0.isEmpty ? nil : $0 }
        ?? resourceScopes.flatMap { $0.isEmpty ? nil : $0 }
        ?? clientMetadata.scope

    if authorizationCode == nil { clientInformation = try await provider.clientInformation() }
    if let client = clientInformation, client.issuer != nil {
        let stored: OAuthAuthorizationServerInformation?
        if let callbackInformation { stored = callbackInformation }
        else { stored = try await storedAuthorizationServerInformation(provider: provider, clientInformation: client) }
        if let stored { try assertAuthorizationServerMatches(stored, currentInformation) }
    }

    if clientInformation == nil {
        guard authorizationCode == nil else {
            throw MCPClientError(message: "Existing OAuth client information is required when exchanging an authorization code")
        }
        guard let saveClientInformation = provider.saveClientInformation else {
            throw MCPClientError(message: "OAuth client information must be saveable for dynamic registration")
        }
        clientMetadata.scope = selectedScope
        let full = try await registerClient(
            authorizationServerUrl: authorizationServerUrl, metadata: metadata,
            clientMetadata: clientMetadata, fetchFn: fetchFn
        )
        let client = try pinClientInformation(OAuthClientInformation(full), to: currentInformation)
        try await saveClientInformation(client)
        clientInformation = client
    }
    let client = clientInformation!

    if let authorizationCode {
        if let expected = try await provider.storedState?(), expected != callbackState {
            throw MCPClientError(message: "OAuth state parameter mismatch - possible CSRF attack")
        }
        let callbackPin: OAuthAuthorizationServerInformation?
        if let callbackInformation { callbackPin = callbackInformation }
        else { callbackPin = try await storedAuthorizationServerInformation(provider: provider, clientInformation: client) }
        guard let stored = callbackPin else {
            throw MCPClientOAuthError(message: "Stored OAuth authorization server metadata is required when exchanging an authorization code")
        }
        let expectedIssuer = stored.issuer ?? metadata?.issuer ?? authorizationServerUrl.absoluteString
        if let callbackIssuer, callbackIssuer != expectedIssuer {
            throw MCPClientOAuthError(message: "OAuth authorization response issuer \(callbackIssuer) does not match expected issuer \(expectedIssuer)")
        }
        try assertAuthorizationServerMatches(stored, currentInformation)
        let verifier = try await provider.codeVerifier()
        let tokens = try await exchangeAuthorization(
            authorizationServerUrl: authorizationServerUrl, metadata: metadata, clientInformation: client,
            authorizationCode: authorizationCode, codeVerifier: verifier, redirectUri: provider.redirectUrl,
            resource: resource, addClientAuthentication: provider.addClientAuthentication, fetchFn: fetchFn
        )
        try await provider.saveTokens(pinTokens(tokens, to: currentInformation))
        return .authorized
    }

    if let tokens = try await provider.tokens(), let refreshToken = tokens.refreshToken, !refreshToken.isEmpty {
        let stored = try await storedAuthorizationServerInformation(provider: provider, clientInformation: client, tokens: tokens)
        if let stored {
            try assertAuthorizationServerMatches(stored, currentInformation)
        } else {
            try await provider.invalidateCredentials?(.tokens, OAuthCredentialInvalidationContext(tokens: tokens))
        }
        if stored != nil {
            do {
                refreshAttempt = tokens
                let refreshed = try await refreshAuthorization(
                    authorizationServerUrl: authorizationServerUrl, metadata: metadata, clientInformation: client,
                    refreshToken: refreshToken, resource: resource,
                    addClientAuthentication: provider.addClientAuthentication, fetchFn: fetchFn
                )
                try await provider.saveTokens(pinTokens(refreshed, to: currentInformation))
                return .authorized
            } catch {
                if MCPClientOAuthError.isInstance(error), !(error is ServerError) { throw error }
            }
        }
    }

    let state = try await provider.state?()
    if let state, !state.isEmpty { try await provider.saveState?(state) }
    let authorization = try startAuthorization(
        authorizationServerUrl: authorizationServerUrl, metadata: metadata, clientInformation: client,
        redirectUrl: provider.redirectUrl, scope: selectedScope, state: state, resource: resource
    )
    if let save = provider.saveAuthorizationServerInformation {
        try await save(currentInformation)
    } else if let save = provider.saveClientInformation {
        try await save(pinClientInformation(client, to: currentInformation))
    } else {
        throw MCPClientOAuthError(message: "OAuth authorization server metadata must be saveable before starting authorization")
    }
    try await provider.saveCodeVerifier(authorization.codeVerifier)
    try await provider.redirectToAuthorization(authorization.authorizationUrl)
    return .redirect
}

/**
 Tests for OAuth authorization helpers used by MCP transports.
 
 Port of selected cases from `packages/mcp/src/tool/oauth.test.ts`.
 */

import Foundation
import Testing

import SwiftAISDK
import AISDKProviderUtils

private func queryValue(_ url: URL, name: String) -> String? {
    let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    return components?.queryItems?.first(where: { $0.name == name })?.value
}

@Suite("MCP OAuth Authorization")
struct OAuthAuthorizationTests {

    private func makeClientInfo() -> OAuthClientInformation {
        OAuthClientInformation(
            clientId: "client123",
            clientSecret: "secret123",
            clientIdIssuedAt: nil,
            clientSecretExpiresAt: nil
        )
    }

    private func makeMetadata(
        responseTypesSupported: [String] = ["code"],
        codeChallengeMethodsSupported: [String]? = ["S256"]
    ) throws -> AuthorizationServerMetadata {
        AuthorizationServerMetadata(
            issuer: "https://auth.example.com",
            authorizationEndpoint: try SafeURL(#require(URL(string: "https://auth.example.com/auth"))),
            tokenEndpoint: try SafeURL(#require(URL(string: "https://auth.example.com/tkn"))),
            registrationEndpoint: nil,
            scopesSupported: nil,
            responseTypesSupported: responseTypesSupported,
            grantTypesSupported: nil,
            codeChallengeMethodsSupported: codeChallengeMethodsSupported,
            tokenEndpointAuthMethodsSupported: nil,
            tokenEndpointAuthSigningAlgValuesSupported: nil
        )
    }

    // MARK: - startAuthorization

    @Test("startAuthorization generates authorization URL with PKCE challenge")
    func startAuthorizationGeneratesAuthorizationURL() throws {
        let authorizationServerUrl = try #require(URL(string: "https://auth.example.com"))
        let redirectUrl = try #require(URL(string: "http://localhost:3000/callback"))
        let resource = try #require(URL(string: "https://api.example.com/mcp-server"))

        let result = try startAuthorization(
            authorizationServerUrl: authorizationServerUrl,
            metadata: nil,
            clientInformation: makeClientInfo(),
            redirectUrl: redirectUrl,
            scope: nil,
            state: nil,
            resource: resource
        )

        #expect(result.authorizationUrl.absoluteString.hasPrefix("https://auth.example.com/authorize?"))
        #expect(queryValue(result.authorizationUrl, name: "response_type") == "code")
        #expect(queryValue(result.authorizationUrl, name: "client_id") == "client123")
        #expect(queryValue(result.authorizationUrl, name: "code_challenge_method") == "S256")
        #expect(queryValue(result.authorizationUrl, name: "redirect_uri") == "http://localhost:3000/callback")
        #expect(queryValue(result.authorizationUrl, name: "resource") == "https://api.example.com/mcp-server")

        let codeChallenge = queryValue(result.authorizationUrl, name: "code_challenge") ?? ""
        #expect(!codeChallenge.isEmpty)
        #expect(!result.codeVerifier.isEmpty)
    }

    @Test("startAuthorization includes scope parameter when provided")
    func startAuthorizationIncludesScope() throws {
        let result = try startAuthorization(
            authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
            metadata: nil,
            clientInformation: makeClientInfo(),
            redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
            scope: "read write profile",
            state: nil,
            resource: nil
        )

        #expect(queryValue(result.authorizationUrl, name: "scope") == "read write profile")
    }

    @Test("startAuthorization excludes scope parameter when not provided")
    func startAuthorizationExcludesScope() throws {
        let result = try startAuthorization(
            authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
            metadata: nil,
            clientInformation: makeClientInfo(),
            redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
            scope: nil,
            state: nil,
            resource: nil
        )

        #expect(queryValue(result.authorizationUrl, name: "scope") == nil)
    }

    @Test("startAuthorization includes state parameter when provided")
    func startAuthorizationIncludesState() throws {
        let result = try startAuthorization(
            authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
            metadata: nil,
            clientInformation: makeClientInfo(),
            redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
            scope: nil,
            state: "foobar",
            resource: nil
        )

        #expect(queryValue(result.authorizationUrl, name: "state") == "foobar")
    }

    @Test("startAuthorization excludes state parameter when not provided")
    func startAuthorizationExcludesState() throws {
        let result = try startAuthorization(
            authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
            metadata: nil,
            clientInformation: makeClientInfo(),
            redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
            scope: nil,
            state: nil,
            resource: nil
        )

        #expect(queryValue(result.authorizationUrl, name: "state") == nil)
    }

    @Test("startAuthorization includes consent prompt parameter if scope includes offline_access")
    func startAuthorizationOfflineAccessAddsPrompt() throws {
        let result = try startAuthorization(
            authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
            metadata: nil,
            clientInformation: makeClientInfo(),
            redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
            scope: "read write profile offline_access",
            state: nil,
            resource: nil
        )

        #expect(queryValue(result.authorizationUrl, name: "prompt") == "consent")
    }

    @Test("startAuthorization uses metadata authorization_endpoint when provided")
    func startAuthorizationUsesAuthorizationEndpointFromMetadata() throws {
        let metadata = try makeMetadata()

        let result = try startAuthorization(
            authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
            metadata: metadata,
            clientInformation: makeClientInfo(),
            redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
            scope: nil,
            state: nil,
            resource: nil
        )

        #expect(result.authorizationUrl.absoluteString.hasPrefix("https://auth.example.com/auth?"))
    }

    @Test("startAuthorization validates response type support")
    func startAuthorizationValidatesResponseType() throws {
        let metadata = try makeMetadata(responseTypesSupported: ["token"])

        do {
            _ = try startAuthorization(
                authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
                metadata: metadata,
                clientInformation: makeClientInfo(),
                redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
                scope: nil,
                state: nil,
                resource: nil
            )
            Issue.record("Expected error")
        } catch let error as MCPClientError {
            #expect(error.message.contains("does not support response type"))
        }
    }

    @Test("startAuthorization requires advertised S256 PKCE", arguments: [["plain"], nil] as [[String]?])
    func startAuthorizationValidatesPKCE(methods: [String]?) throws {
        let metadata = try makeMetadata(
            responseTypesSupported: ["code"],
            codeChallengeMethodsSupported: methods
        )

        do {
            _ = try startAuthorization(
                authorizationServerUrl: #require(URL(string: "https://auth.example.com")),
                metadata: metadata,
                clientInformation: makeClientInfo(),
                redirectUrl: #require(URL(string: "http://localhost:3000/callback")),
                scope: nil,
                state: nil,
                resource: nil
            )
            Issue.record("Expected error")
        } catch let error as MCPClientError {
            #expect(error.message.contains("does not support code challenge method"))
        }
    }

    // MARK: - parseErrorResponse

    @Test("parseErrorResponse maps known OAuth error codes to MCPClientOAuthError types")
    func parseErrorResponseMapsKnownErrorCodes() throws {
        let body = """
        {"error":"invalid_client","error_description":"nope"}
        """

        let error = parseErrorResponse(statusCode: 400, body: body)
        #expect(error is InvalidClientError)

        let typed = try #require(error as? InvalidClientError)
        #expect(typed.message == "nope")
    }

    @Test("parseErrorResponse defaults to ServerError for unknown error codes")
    func parseErrorResponseUnknownErrorDefaultsToServerError() throws {
        let body = """
        {"error":"some_new_error","error_description":"wat"}
        """

        let error = parseErrorResponse(statusCode: 400, body: body)
        #expect(error is ServerError)

        let typed = try #require(error as? ServerError)
        #expect(typed.message == "wat")
    }

    @Test("parseErrorResponse returns ServerError on invalid JSON body with raw body included")
    func parseErrorResponseInvalidJSONBody() throws {
        let body = "not-json"

        let error = parseErrorResponse(statusCode: 400, body: body)
        let typed = try #require(error as? ServerError)

        #expect(typed.message.contains("HTTP 400: Invalid OAuth error response:"))
        #expect(typed.message.contains("Raw body: not-json"))
    }
}

private actor OAuthStore {
    var client: OAuthClientInformation?
    var savedTokens: OAuthTokens?
    var pin: OAuthAuthorizationServerInformation?
    var redirect: URL?
    var verifier = "verifier"
    var savedState: String?
    var invalidations: [OAuthCredentialInvalidationContext] = []

    init(client: OAuthClientInformation? = OAuthClientInformation(clientId: "client"), tokens: OAuthTokens? = nil) {
        self.client = client
        self.savedTokens = tokens
    }

    func saveClient(_ client: OAuthClientInformation) { self.client = client }
    func saveTokens(_ tokens: OAuthTokens) { savedTokens = tokens }
    func savePin(_ pin: OAuthAuthorizationServerInformation) { self.pin = pin }
    func saveRedirect(_ url: URL) { redirect = url }
    func saveVerifier(_ verifier: String) { self.verifier = verifier }
    func saveState(_ state: String) { savedState = state }
    func invalidate(_ scope: OAuthCredentialInvalidationScope, _ context: OAuthCredentialInvalidationContext?) {
        if scope == .all { client = nil; savedTokens = nil }
        if scope == .tokens {
            if let context { invalidations.append(context) }
            if context == nil || (savedTokens?.accessToken == context?.tokens.accessToken
                && savedTokens?.refreshToken == context?.tokens.refreshToken) {
                savedTokens = nil
            }
        }
    }
}

private struct FlowProvider: OAuthClientProvider {
    let store: OAuthStore
    let clientMetadata: OAuthClientMetadata
    var separatePin = true
    var dynamic = false
    var state: OAuthStateProvider? = { "flow-state" }
    let redirectUrl = URL(string: "http://localhost:3000/callback")!

    init(store: OAuthStore, separatePin: Bool = true, dynamic: Bool = false) throws {
        self.store = store
        self.separatePin = separatePin
        self.dynamic = dynamic
        self.clientMetadata = OAuthClientMetadata(
            redirectUris: [try SafeURL(URL(string: "http://localhost:3000/callback")!)], scope: "client.scope"
        )
    }

    func tokens() async throws -> OAuthTokens? { await store.savedTokens }
    func saveTokens(_ tokens: OAuthTokens) async throws { await store.saveTokens(tokens) }
    func redirectToAuthorization(_ url: URL) async throws { await store.saveRedirect(url) }
    func saveCodeVerifier(_ verifier: String) async throws { await store.saveVerifier(verifier) }
    func codeVerifier() async throws -> String { await store.verifier }
    func clientInformation() async throws -> OAuthClientInformation? { await store.client }
    func isClientInformationDynamicallyRegistered() async throws -> Bool { dynamic }
    func authorizationServerInformation() async throws -> OAuthAuthorizationServerInformation? { await store.pin }
    var saveClientInformation: OAuthSaveClientInformation? { { await store.saveClient($0) } }
    var saveAuthorizationServerInformation: OAuthSaveAuthorizationServerInformation? {
        guard separatePin else { return nil }
        return { await store.savePin($0) }
    }
    var saveState: OAuthSaveState? { { await store.saveState($0) } }
    var storedState: OAuthStoredState? { { await store.savedState } }
    var invalidateCredentials: OAuthInvalidateCredentials? { { await store.invalidate($0, $1) } }
}

private func oauthResponse(_ request: URLRequest, status: Int = 200, json: [String: Any]) throws -> (Data, HTTPURLResponse) {
    (try JSONSerialization.data(withJSONObject: json), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
}

private actor OAuthServer {
    var requests: [URLRequest] = []
    var scopes: [String]?
    var protectedMetadataAvailable = true
    var tokenEndpoint = "https://auth.example.com/token"
    let serverUrl = URL(string: "https://resource.example.com/mcp")!

    init(scopes: [String]? = nil) { self.scopes = scopes }
    func hideProtectedMetadata() { protectedMetadataAvailable = false }
    func changeTokenEndpoint() { tokenEndpoint = "https://auth.example.com/changed-token" }
    func fetch(_ request: URLRequest) throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let url = request.url!
        if url.path.contains("oauth-protected-resource"), protectedMetadataAvailable {
            var metadata: [String: Any] = ["resource": serverUrl.absoluteString, "authorization_servers": ["https://auth.example.com"]]
            if let scopes { metadata["scopes_supported"] = scopes }
            return try oauthResponse(request, json: metadata)
        }
        if url.host == "auth.example.com", url.path.contains("oauth-authorization-server") {
            return try oauthResponse(request, json: [
                "issuer": "https://auth.example.com", "authorization_endpoint": "https://auth.example.com/authorize",
                "token_endpoint": tokenEndpoint, "registration_endpoint": "https://auth.example.com/register",
                "response_types_supported": ["code"], "code_challenge_methods_supported": ["S256"],
            ])
        }
        if url.path == "/register" {
            var body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
            body["client_id"] = "registered-client"
            return try oauthResponse(request, json: body)
        }
        if url.absoluteString == tokenEndpoint {
            return try oauthResponse(request, json: ["access_token": "issued-access", "token_type": "Bearer"])
        }
        return try oauthResponse(request, status: 404, json: [:])
    }
}

private func flowPin() -> OAuthAuthorizationServerInformation {
    OAuthAuthorizationServerInformation(
        issuer: "https://auth.example.com", authorizationServerUrl: URL(string: "https://auth.example.com")!,
        tokenEndpoint: URL(string: "https://auth.example.com/token")!
    )
}

private enum ScopeSource: CaseIterable, Sendable {
    case challenge, resource, client, emptyChallenge
    var scope: String? { self == .challenge ? "challenge.scope" : self == .emptyChallenge ? "" : nil }
    var scopes: [String]? { self == .client ? [] : ["resource.read", "resource.write"] }
    var expected: String {
        switch self {
        case .challenge: "challenge.scope"
        case .resource, .emptyChallenge: "resource.read resource.write"
        case .client: "client.scope"
        }
    }
}

extension OAuthAuthorizationTests {
    @Test("auth uses one selected scope for registration and authorization", arguments: ScopeSource.allCases)
    fileprivate func selectedScope(source: ScopeSource) async throws {
        let store = OAuthStore(client: nil)
        let provider = try FlowProvider(store: store, separatePin: false)
        let server = OAuthServer(scopes: source.scopes)
        let result = try await auth(provider, serverUrl: server.serverUrl, scope: source.scope, fetchFn: { try await server.fetch($0) })
        #expect(result == .redirect)
        let redirect = try #require(await store.redirect)
        #expect(queryValue(redirect, name: "scope") == source.expected)
        let registration = try #require(await server.requests.first { $0.url?.path == "/register" })
        let body = try #require(JSONSerialization.jsonObject(with: registration.httpBody!) as? [String: Any])
        #expect(body["scope"] as? String == source.expected)
        #expect(body["application_type"] as? String == "native")
        #expect(await store.client?.issuer?.url.absoluteString == "https://auth.example.com")
        #expect(await store.client?.tokenEndpoint?.url.absoluteString == "https://auth.example.com/token")
    }

    @Test("callback reuses the pinned external authorization server when PRM is unavailable")
    func externalAuthorizationServerCallback() async throws {
        let store = OAuthStore()
        let provider = try FlowProvider(store: store)
        let server = OAuthServer()
        let initial = try await auth(provider, serverUrl: server.serverUrl, fetchFn: { try await server.fetch($0) })
        #expect(initial == .redirect)
        #expect(await store.savedState == "flow-state")
        await server.hideProtectedMetadata()
        let result = try await auth(
            provider, serverUrl: server.serverUrl, authorizationCode: "authorization-code",
            callbackState: "flow-state", callbackIssuer: "https://auth.example.com", fetchFn: { try await server.fetch($0) }
        )
        #expect(result == .authorized)
        let tokens = try #require(await store.savedTokens)
        #expect(tokens.accessToken == "issued-access")
        #expect(tokens.authorizationServer?.url.absoluteString == "https://auth.example.com/")
        let restored = try JSONDecoder().decode(OAuthTokens.self, from: JSONEncoder().encode(tokens))
        #expect(restored == tokens)
        let request = try #require(await server.requests.first { $0.httpMethod == "POST" })
        #expect(request.url?.absoluteString == "https://auth.example.com/token")
        #expect(request.fetchRedirectMode == .error)
        let params = try #require(String(data: request.httpBody!, encoding: .utf8))
        #expect(params.contains("code=authorization-code"))
        #expect(params.contains("code_verifier="))
    }

    @Test("callback rejects mismatched state, issuer, or credential pin before token POST", arguments: ["state", "issuer", "pin"])
    func rejectsCallbackMismatch(kind: String) async throws {
        let store = OAuthStore()
        let provider = try FlowProvider(store: store)
        let server = OAuthServer()
        _ = try await auth(provider, serverUrl: server.serverUrl, fetchFn: { try await server.fetch($0) })
        if kind == "pin" { await server.changeTokenEndpoint() }
        do {
            _ = try await auth(
                provider, serverUrl: server.serverUrl, authorizationCode: "secret-code",
                callbackState: kind == "state" ? "attacker-state" : "flow-state",
                callbackIssuer: kind == "issuer" ? "https://other.example.com" : "https://auth.example.com",
                fetchFn: { try await server.fetch($0) }
            )
            Issue.record("Expected callback refusal")
        } catch {
            if kind == "pin" {
                #expect(AuthorizationServerMismatchError.isInstance(error))
                #expect(MCPClientOAuthError.isInstance(error))
            } else if kind == "issuer" {
                #expect(error is MCPClientOAuthError)
            } else {
                #expect(error is MCPClientError)
            }
        }
        #expect(await server.requests.filter { $0.httpMethod == "POST" }.isEmpty)
        #expect(await store.savedTokens == nil)
    }

    @Test("failed refresh invalidates only its token generation and preserves a concurrent replacement")
    func refreshGeneration() async throws {
        let old = OAuthTokens(accessToken: "old-access", tokenType: "Bearer", refreshToken: "old-refresh")
        let replacement = OAuthTokens(accessToken: "winner-access", tokenType: "Bearer", refreshToken: "winner-refresh")
        let store = OAuthStore(tokens: old)
        await store.savePin(flowPin())
        let provider = try FlowProvider(store: store)
        let server = OAuthServer()
        let result = try await auth(provider, serverUrl: server.serverUrl, fetchFn: { request in
            if request.url?.path == "/token", String(data: request.httpBody!, encoding: .utf8)?.contains("refresh_token=old-refresh") == true {
                await store.saveTokens(replacement)
                return try oauthResponse(request, status: 400, json: ["error": "invalid_grant"])
            }
            return try await server.fetch(request)
        })
        #expect(result == .authorized)
        #expect(await store.savedTokens?.accessToken == "issued-access")
        #expect(await store.savedTokens?.refreshToken == "winner-refresh")
        #expect(await store.invalidations.map(\.tokens) == [old])
        #expect(await store.redirect == nil)
    }

    @Test("code-exchange errors preserve existing credentials", arguments: ["invalid_grant", "invalid_client", "unauthorized_client"])
    func rejectedCodePreservesCredentials(code: String) async throws {
        let tokens = OAuthTokens(accessToken: "saved-access", tokenType: "Bearer", refreshToken: "saved-refresh")
        let store = OAuthStore(tokens: tokens)
        await store.savePin(flowPin())
        let provider = try FlowProvider(store: store, dynamic: true)
        let server = OAuthServer()
        do {
            _ = try await auth(provider, serverUrl: server.serverUrl, authorizationCode: "rejected-code", fetchFn: { request in
                if request.url?.path == "/token" { return try oauthResponse(request, status: 400, json: ["error": code]) }
                return try await server.fetch(request)
            })
            Issue.record("Expected OAuth error")
        } catch {
            switch code {
            case "invalid_grant": #expect(error is InvalidGrantError)
            case "invalid_client": #expect(error is InvalidClientError)
            default: #expect(error is UnauthorizedClientError)
            }
        }
        #expect(await store.savedTokens == tokens)
        #expect(await store.client?.clientId == "client")
    }

    @Test("client errors only re-register dynamically registered clients", arguments: [false, true])
    func dynamicRegistrationRecovery(dynamic: Bool) async throws {
        let store = OAuthStore(tokens: OAuthTokens(accessToken: "expired", tokenType: "Bearer", refreshToken: "refresh"))
        await store.savePin(flowPin())
        let provider = try FlowProvider(store: store, dynamic: dynamic)
        let server = OAuthServer()
        do {
            let result = try await auth(provider, serverUrl: server.serverUrl, fetchFn: { request in
                if request.url?.path == "/token" { return try oauthResponse(request, status: 401, json: ["error": "invalid_client"]) }
                return try await server.fetch(request)
            })
            #expect(dynamic)
            #expect(result == .redirect)
            #expect(await store.client?.clientId == "registered-client")
        } catch is InvalidClientError {
            #expect(!dynamic)
            #expect(await store.client?.clientId == "client")
            #expect(await store.savedTokens?.refreshToken == "refresh")
        }
    }

    @Test("registration infers application type and preserves an explicit choice", arguments: ["custom", "remote", "explicit"])
    func applicationType(kind: String) async throws {
        let server = OAuthServer()
        let uri = kind == "remote" ? "https://app.example.com/callback" : "myapp:/callback"
        let metadata = OAuthClientMetadata(
            redirectUris: [try SafeURL(URL(string: uri)!)], applicationType: kind == "explicit" ? .web : nil
        )
        let info = try await registerClient(authorizationServerUrl: URL(string: "https://auth.example.com")!, metadata: nil, clientMetadata: metadata, fetchFn: { try await server.fetch($0) })
        #expect(info.applicationType == (kind == "custom" ? .native : .web))
    }

    @Test("auth rejects cross-origin PRM hints and remote-advertised loopback authorization servers", arguments: ["hint", "loopback"])
    func discoveryBoundarySafety(kind: String) async throws {
        let provider = try FlowProvider(store: OAuthStore())
        let server = URL(string: "https://resource.example.com/mcp")!
        await #expect(throws: MCPClientOAuthError.self) {
            _ = try await auth(
                provider, serverUrl: server,
                resourceMetadataUrl: kind == "hint" ? URL(string: "https://foreign.example.com/metadata")! : nil,
                fetchFn: { request in
                    if kind == "hint" || request.url?.host != "resource.example.com" {
                        Issue.record("Unapproved OAuth discovery target was requested")
                    }
                    return try oauthResponse(request, json: ["resource": server.absoluteString, "authorization_servers": ["http://localhost:4000"]])
                }
            )
        }
    }

    @Test("token requests serialize origin resources and preserve refresh credentials")
    func tokenRequestBoundary() async throws {
        let server = URL(string: "http://localhost:4000")!
        let tokens = try await refreshAuthorization(
            authorizationServerUrl: server, metadata: nil, clientInformation: makeClientInfo(), refreshToken: "refresh+token",
            resource: URL(string: "https://resource.example.com/")!, fetchFn: { request in
                let body = try #require(String(data: request.httpBody!, encoding: .utf8))
                let fields = URLComponents(string: "https://example.com/?" + body)?.queryItems
                #expect(fields?.first { $0.name == "resource" }?.value == "https://resource.example.com")
                #expect(fields?.first { $0.name == "refresh_token" }?.value == "refresh+token")
                #expect(request.url?.absoluteString == "http://localhost:4000/token")
                #expect(request.fetchRedirectMode == .error)
                return try oauthResponse(request, json: ["access_token": "refreshed-access", "token_type": "Bearer"])
            }
        )
        #expect(tokens.accessToken == "refreshed-access")
        #expect(tokens.refreshToken == "refresh+token")
    }

    @Test("authorization replaces preexisting OAuth query values")
    func replacesAuthorizationParameters() throws {
        let endpoint = URL(string: "https://auth.example.com/authorize?client_id=stale&scope=stale&tenant=blue")!
        let metadata = AuthorizationServerMetadata(
            issuer: "https://auth.example.com", authorizationEndpoint: try SafeURL(endpoint),
            tokenEndpoint: try SafeURL(URL(string: "https://auth.example.com/token")!), responseTypesSupported: ["code"],
            codeChallengeMethodsSupported: ["S256"]
        )
        let authorization = try startAuthorization(
            authorizationServerUrl: URL(string: "https://auth.example.com")!, metadata: metadata,
            clientInformation: makeClientInfo(), redirectUrl: URL(string: "myapp:/callback")!, scope: "selected"
        )
        let parameters = try #require(URLComponents(url: authorization.authorizationUrl, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(parameters.filter { $0.name == "client_id" }.map(\.value) == ["client123"])
        #expect(parameters.filter { $0.name == "scope" }.map(\.value) == ["selected"])
        #expect(queryValue(authorization.authorizationUrl, name: "tenant") == "blue")
    }

    @Test("OAuth credential operations reject private endpoints and redirect responses", arguments: ["exchange", "refresh", "register"])
    func credentialEndpointSafety(operation: String) async throws {
        let serverUrl = URL(string: "https://auth.example.com")!
        let endpoint = try SafeURL(URL(string: "http://169.254.169.254/credentials")!)
        let metadata = AuthorizationServerMetadata(
            issuer: serverUrl.absoluteString, authorizationEndpoint: try SafeURL(serverUrl), tokenEndpoint: endpoint,
            registrationEndpoint: endpoint, responseTypesSupported: ["code"]
        )
        let clientMetadata = OAuthClientMetadata(redirectUris: [try SafeURL(URL(string: "myapp:/callback")!)])
        let blockedFetch: MCPFetchFunction = { _ in
            Issue.record("Credentials reached a private endpoint")
            throw URLError(.badURL)
        }
        let redirectFetch: MCPFetchFunction = { request in
            #expect(request.fetchRedirectMode == .error)
            return (Data(), HTTPURLResponse(url: request.url!, statusCode: 307, httpVersion: nil, headerFields: ["Location": "https://other.example.com/steal"])!)
        }
        for isPrivate in [true, false] {
            let selectedMetadata = isPrivate ? metadata : nil
            let fetch = isPrivate ? blockedFetch : redirectFetch
            do {
                switch operation {
                case "exchange":
                    _ = try await exchangeAuthorization(authorizationServerUrl: serverUrl, metadata: selectedMetadata, clientInformation: makeClientInfo(), authorizationCode: "code", codeVerifier: "verifier", redirectUri: URL(string: "myapp:/callback")!, fetchFn: fetch)
                case "refresh":
                    _ = try await refreshAuthorization(authorizationServerUrl: serverUrl, metadata: selectedMetadata, clientInformation: makeClientInfo(), refreshToken: "refresh", fetchFn: fetch)
                default:
                    _ = try await registerClient(authorizationServerUrl: serverUrl, metadata: selectedMetadata, clientMetadata: clientMetadata, fetchFn: fetch)
                }
                Issue.record("Expected unsafe credential request refusal")
            } catch {
                if isPrivate { #expect(error is MCPClientOAuthError) }
                else { #expect(error is AISDKProviderUtils.DownloadError) }
            }
        }
    }
}


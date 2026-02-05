/**
 Tests for OAuth authorization helpers used by MCP transports.
 
 Port of selected cases from `packages/mcp/src/tool/oauth.test.ts`.
 */

import Foundation
import Testing

@testable import SwiftAISDK

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

    @Test("startAuthorization validates PKCE support")
    func startAuthorizationValidatesPKCE() throws {
        let metadata = try makeMetadata(
            responseTypesSupported: ["code"],
            codeChallengeMethodsSupported: ["plain"]
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


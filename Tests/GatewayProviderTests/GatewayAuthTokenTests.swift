import Foundation
import Testing
@testable import GatewayProvider

@Suite("Gateway auth token resolution", .serialized)
struct GatewayAuthTokenTests {
    private struct EnvSnapshot {
        let apiKey: String?
        let oidcToken: String?

        init() {
            apiKey = getenv("AI_GATEWAY_API_KEY").flatMap { String(validatingCString: $0) }
            oidcToken = getenv("VERCEL_OIDC_TOKEN").flatMap { String(validatingCString: $0) }
        }

        func restore() {
            if let apiKey {
                setenv("AI_GATEWAY_API_KEY", apiKey, 1)
            } else {
                unsetenv("AI_GATEWAY_API_KEY")
            }

            if let oidcToken {
                setenv("VERCEL_OIDC_TOKEN", oidcToken, 1)
            } else {
                unsetenv("VERCEL_OIDC_TOKEN")
            }
        }
    }

    @Test("settings.apiKey takes precedence over environment variables")
    func settingsApiKeyTakesPrecedence() async throws {
        let snapshot = EnvSnapshot()
        defer { snapshot.restore() }

        setenv("AI_GATEWAY_API_KEY", "env-api-key", 1)
        setenv("VERCEL_OIDC_TOKEN", "env-oidc-token", 1)

        let token = try await getGatewayAuthToken(settings: .init(apiKey: "options-api-key"))
        #expect(token.authMethod == .apiKey)
        #expect(token.token == "options-api-key")
    }

    @Test("AI_GATEWAY_API_KEY is used when settings.apiKey is not provided")
    func envApiKeyIsUsed() async throws {
        let snapshot = EnvSnapshot()
        defer { snapshot.restore() }

        setenv("AI_GATEWAY_API_KEY", "env-api-key", 1)
        setenv("VERCEL_OIDC_TOKEN", "env-oidc-token", 1)

        let token = try await getGatewayAuthToken(settings: .init())
        #expect(token.authMethod == .apiKey)
        #expect(token.token == "env-api-key")
    }

    @Test("falls back to Vercel OIDC token when no API key is available")
    func fallsBackToOidc() async throws {
        let snapshot = EnvSnapshot()
        defer { snapshot.restore() }

        unsetenv("AI_GATEWAY_API_KEY")
        setenv("VERCEL_OIDC_TOKEN", "oidc-token", 1)

        let token = try await getGatewayAuthToken(settings: .init())
        #expect(token.authMethod == .oidc)
        #expect(token.token == "oidc-token")
    }

    @Test("empty-string env vars are treated as missing")
    func emptyStringEnvVarsAreMissing() async throws {
        let snapshot = EnvSnapshot()
        defer { snapshot.restore() }

        setenv("AI_GATEWAY_API_KEY", "", 1)
        setenv("VERCEL_OIDC_TOKEN", "", 1)

        do {
            _ = try await getGatewayAuthToken(settings: .init())
            Issue.record("Expected auth resolution to throw")
        } catch {
            #expect(true)
        }
    }

    @Test("whitespace API key is treated as a valid value (no trimming)")
    func whitespaceApiKeyIsValid() async throws {
        let snapshot = EnvSnapshot()
        defer { snapshot.restore() }

        setenv("AI_GATEWAY_API_KEY", "\t\n ", 1)
        unsetenv("VERCEL_OIDC_TOKEN")

        let token = try await getGatewayAuthToken(settings: .init())
        #expect(token.authMethod == .apiKey)
        #expect(token.token == "\t\n ")
    }
}


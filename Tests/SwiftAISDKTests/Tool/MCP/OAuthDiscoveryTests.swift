/**
 Tests for OAuth discovery helpers used by MCP transports.
 
 Port of selected cases from `packages/mcp/src/tool/oauth.test.ts`.
 */

import Foundation
import Testing

@testable import SwiftAISDK

private struct OAuthTestError: Error, LocalizedError, Sendable, Equatable {
    let message: String
    var errorDescription: String? { message }
}

private actor FetchRecorder {
    private var callCount = 0
    private let handler: @Sendable (_ call: Int, _ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    private(set) var requests: [URLRequest] = []

    init(
        handler: @escaping @Sendable (_ call: Int, _ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    ) {
        self.handler = handler
    }

    func fetch(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        callCount += 1
        requests.append(request)
        return try await handler(callCount, request)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}

private func makeHTTPResponse(
    url: URL,
    statusCode: Int,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: headers)!
}

@Suite("MCP OAuth Discovery")
struct OAuthDiscoveryTests {

    // MARK: - extractResourceMetadataUrl

    @Test("extractResourceMetadataUrl returns resource metadata url when present")
    func extractResourceMetadataUrlPresent() throws {
        let resourceUrl = "https://resource.example.com/.well-known/oauth-protected-resource"
        let responseUrl = try #require(URL(string: "https://resource.example.com/"))
        let response = try #require(
            HTTPURLResponse(
                url: responseUrl,
                statusCode: 401,
                httpVersion: nil,
                headerFields: [
                    "WWW-Authenticate": "Bearer realm=\"mcp\", resource_metadata=\"\(resourceUrl)\"",
                ]
            )
        )

        #expect(extractResourceMetadataUrl(response)?.absoluteString == resourceUrl)
    }

    @Test("extractResourceMetadataUrl returns nil if not bearer")
    func extractResourceMetadataUrlNotBearer() throws {
        let resourceUrl = "https://resource.example.com/.well-known/oauth-protected-resource"
        let responseUrl = try #require(URL(string: "https://resource.example.com/"))
        let response = try #require(
            HTTPURLResponse(
                url: responseUrl,
                statusCode: 401,
                httpVersion: nil,
                headerFields: [
                    "WWW-Authenticate": "Basic realm=\"mcp\", resource_metadata=\"\(resourceUrl)\"",
                ]
            )
        )

        #expect(extractResourceMetadataUrl(response) == nil)
    }

    @Test("extractResourceMetadataUrl returns nil if resource_metadata not present")
    func extractResourceMetadataUrlMissingMetadataParam() throws {
        let responseUrl = try #require(URL(string: "https://resource.example.com/"))
        let response = try #require(
            HTTPURLResponse(
                url: responseUrl,
                statusCode: 401,
                httpVersion: nil,
                headerFields: [
                    "WWW-Authenticate": "Bearer realm=\"mcp\"",
                ]
            )
        )

        #expect(extractResourceMetadataUrl(response) == nil)
    }

    @Test("extractResourceMetadataUrl returns nil on invalid url")
    func extractResourceMetadataUrlInvalidURL() throws {
        let responseUrl = try #require(URL(string: "https://resource.example.com/"))
        let response = try #require(
            HTTPURLResponse(
                url: responseUrl,
                statusCode: 401,
                httpVersion: nil,
                headerFields: [
                    "WWW-Authenticate": "Bearer realm=\"mcp\", resource_metadata=\"invalid-url\"",
                ]
            )
        )

        #expect(extractResourceMetadataUrl(response) == nil)
    }

    // MARK: - discoverOAuthProtectedResourceMetadata

    @Test("discoverOAuthProtectedResourceMetadata returns metadata when discovery succeeds")
    func discoverOAuthProtectedResourceMetadataReturnsMetadata() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))
        let json = """
        {"resource":"https://resource.example.com","authorization_servers":["https://auth.example.com"]}
        """

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            let response = makeHTTPResponse(url: url, statusCode: 200)
            return (Data(json.utf8), response)
        }

        let metadata = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl,
            fetchFn: { try await recorder.fetch($0) }
        )

        #expect(metadata.resource.absoluteString == "https://resource.example.com")
        #expect(metadata.authorizationServers?.map(\.url.absoluteString) == ["https://auth.example.com"])

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)

        let request = requests[0]
        #expect(request.url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource")
        #expect(request.value(forHTTPHeaderField: "MCP-Protocol-Version") == LATEST_PROTOCOL_VERSION)
    }

    @Test("discoverOAuthProtectedResourceMetadata returns metadata when first fetch fails but second without MCP header succeeds")
    func discoverOAuthProtectedResourceMetadataCorsRetry() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))
        let json = """
        {"resource":"https://resource.example.com","authorization_servers":["https://auth.example.com"]}
        """

        let recorder = FetchRecorder { call, request in
            let url = try #require(request.url)
            if call == 1 {
                throw URLError(.cannotConnectToHost)
            }

            let response = makeHTTPResponse(url: url, statusCode: 200)
            return (Data(json.utf8), response)
        }

        let metadata = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl,
            fetchFn: { try await recorder.fetch($0) }
        )

        #expect(metadata.resource.absoluteString == "https://resource.example.com")

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 2)

        #expect(requests[0].value(forHTTPHeaderField: "MCP-Protocol-Version") == LATEST_PROTOCOL_VERSION)
        #expect(requests[1].value(forHTTPHeaderField: "MCP-Protocol-Version") == nil)
    }

    @Test("discoverOAuthProtectedResourceMetadata throws an error when all fetch attempts fail")
    func discoverOAuthProtectedResourceMetadataAllFetchAttemptsFail() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))

        let recorder = FetchRecorder { call, request in
            _ = request
            if call == 1 {
                throw URLError(.notConnectedToInternet)
            }
            throw OAuthTestError(message: "Second failure")
        }

        do {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
            Issue.record("Expected error")
        } catch let error as OAuthTestError {
            #expect(error == OAuthTestError(message: "Second failure"))
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 2)
    }

    @Test("discoverOAuthProtectedResourceMetadata throws on 404 errors")
    func discoverOAuthProtectedResourceMetadataThrowsOn404() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            let response = makeHTTPResponse(url: url, statusCode: 404)
            return (Data(), response)
        }

        do {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
            Issue.record("Expected error")
        } catch let error as MCPClientError {
            #expect(error.message == "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test("discoverOAuthProtectedResourceMetadata throws on non-404 errors")
    func discoverOAuthProtectedResourceMetadataThrowsOnNon404() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            let response = makeHTTPResponse(url: url, statusCode: 500)
            return (Data(), response)
        }

        do {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
            Issue.record("Expected error")
        } catch let error as MCPClientError {
            #expect(error.message == "HTTP 500 trying to load well-known OAuth protected resource metadata.")
        }
    }

    @Test("discoverOAuthProtectedResourceMetadata validates metadata schema")
    func discoverOAuthProtectedResourceMetadataValidatesSchema() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))
        let invalidJSON = """
        {"scopes_supported":["email","mcp"]}
        """

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            let response = makeHTTPResponse(url: url, statusCode: 200)
            return (Data(invalidJSON.utf8), response)
        }

        await #expect(throws: Error.self) {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
        }
    }

    @Test("discoverOAuthProtectedResourceMetadata returns metadata when discovery succeeds with path")
    func discoverOAuthProtectedResourceMetadataPathAwareDiscovery() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/path/name"))
        let json = """
        {"resource":"https://resource.example.com","authorization_servers":["https://auth.example.com"]}
        """

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            let response = makeHTTPResponse(url: url, statusCode: 200)
            return (Data(json.utf8), response)
        }

        _ = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl,
            fetchFn: { try await recorder.fetch($0) }
        )

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource/path/name")
    }

    @Test("discoverOAuthProtectedResourceMetadata preserves query parameters in path-aware discovery")
    func discoverOAuthProtectedResourceMetadataPreservesQuery() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/path?param=value"))
        let json = """
        {"resource":"https://resource.example.com","authorization_servers":["https://auth.example.com"]}
        """

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            let response = makeHTTPResponse(url: url, statusCode: 200)
            return (Data(json.utf8), response)
        }

        _ = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl,
            fetchFn: { try await recorder.fetch($0) }
        )

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource/path?param=value")
    }

    @Test("discoverOAuthProtectedResourceMetadata falls back to root discovery when path-aware discovery returns 4xx")
    func discoverOAuthProtectedResourceMetadataFallsBackFor4xx() async throws {
        let statusCodes = [400, 401, 403, 404, 410, 422, 429]

        for statusCode in statusCodes {
            let serverUrl = try #require(URL(string: "https://resource.example.com/path/name"))
            let json = """
            {"resource":"https://resource.example.com","authorization_servers":["https://auth.example.com"]}
            """

            let recorder = FetchRecorder { call, request in
                let url = try #require(request.url)
                if call == 1 {
                    return (Data(), makeHTTPResponse(url: url, statusCode: statusCode))
                }
                return (Data(json.utf8), makeHTTPResponse(url: url, statusCode: 200))
            }

            let metadata = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )

            #expect(metadata.resource.absoluteString == "https://resource.example.com")

            let requests = await recorder.recordedRequests()
            #expect(requests.count == 2)

            #expect(requests[0].url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource/path/name")
            #expect(requests[0].value(forHTTPHeaderField: "MCP-Protocol-Version") == LATEST_PROTOCOL_VERSION)

            #expect(requests[1].url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource")
            #expect(requests[1].value(forHTTPHeaderField: "MCP-Protocol-Version") == LATEST_PROTOCOL_VERSION)
        }
    }

    @Test("discoverOAuthProtectedResourceMetadata throws error when both path-aware and root discovery return 404")
    func discoverOAuthProtectedResourceMetadataBoth404() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/path/name"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            return (Data(), makeHTTPResponse(url: url, statusCode: 404))
        }

        do {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
            Issue.record("Expected error")
        } catch let error as MCPClientError {
            #expect(error.message == "Resource server does not implement OAuth 2.0 Protected Resource Metadata.")
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 2)
    }

    @Test("discoverOAuthProtectedResourceMetadata throws error on 500 status and does not fallback")
    func discoverOAuthProtectedResourceMetadata500NoFallback() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/path/name"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            return (Data(), makeHTTPResponse(url: url, statusCode: 500))
        }

        await #expect(throws: MCPClientError.self) {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test("discoverOAuthProtectedResourceMetadata does not fallback when the original URL is already at root path")
    func discoverOAuthProtectedResourceMetadataNoFallbackRootPath() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            return (Data(), makeHTTPResponse(url: url, statusCode: 404))
        }

        await #expect(throws: MCPClientError.self) {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource")
    }

    @Test("discoverOAuthProtectedResourceMetadata does not fallback when the original URL has no path")
    func discoverOAuthProtectedResourceMetadataNoFallbackNoPath() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            return (Data(), makeHTTPResponse(url: url, statusCode: 404))
        }

        await #expect(throws: MCPClientError.self) {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
    }

    @Test("discoverOAuthProtectedResourceMetadata falls back when path-aware discovery encounters CORS error")
    func discoverOAuthProtectedResourceMetadataFallsBackOnCorsError() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/deep/path"))
        let json = """
        {"resource":"https://resource.example.com","authorization_servers":["https://auth.example.com"]}
        """

        let recorder = FetchRecorder { call, request in
            let url = try #require(request.url)
            switch call {
            case 1:
                throw URLError(.cannotConnectToHost)
            case 2:
                return (Data(), makeHTTPResponse(url: url, statusCode: 404))
            default:
                return (Data(json.utf8), makeHTTPResponse(url: url, statusCode: 200))
            }
        }

        let metadata = try await discoverOAuthProtectedResourceMetadata(
            serverUrl: serverUrl,
            fetchFn: { try await recorder.fetch($0) }
        )
        #expect(metadata.resource.absoluteString == "https://resource.example.com")

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 3)

        #expect(requests[2].url?.absoluteString == "https://resource.example.com/.well-known/oauth-protected-resource")
        #expect(requests[2].value(forHTTPHeaderField: "MCP-Protocol-Version") == LATEST_PROTOCOL_VERSION)
    }

    @Test("discoverOAuthProtectedResourceMetadata does not fallback when resourceMetadataUrl is provided")
    func discoverOAuthProtectedResourceMetadataNoFallbackWhenURLProvided() async throws {
        let serverUrl = try #require(URL(string: "https://resource.example.com/path"))
        let metadataUrl = try #require(URL(string: "https://custom.example.com/metadata"))

        let recorder = FetchRecorder { _, request in
            let url = try #require(request.url)
            return (Data(), makeHTTPResponse(url: url, statusCode: 404))
        }

        await #expect(throws: MCPClientError.self) {
            _ = try await discoverOAuthProtectedResourceMetadata(
                serverUrl: serverUrl,
                resourceMetadataUrl: metadataUrl,
                fetchFn: { try await recorder.fetch($0) }
            )
        }

        let requests = await recorder.recordedRequests()
        #expect(requests.count == 1)
        #expect(requests[0].url?.absoluteString == "https://custom.example.com/metadata")
    }

    // MARK: - buildDiscoveryUrls

    @Test("buildDiscoveryUrls generates correct URLs for server without path")
    func buildDiscoveryUrlsNoPath() throws {
        let url = try #require(URL(string: "https://auth.example.com"))
        let urls = buildDiscoveryUrls(authorizationServerUrl: url)

        let mapped = urls.map { entry in
            let type: String = switch entry.type {
            case .oauth: "oauth"
            case .oidc: "oidc"
            }
            return "\(type):\(entry.url.absoluteString)"
        }

        #expect(mapped.count == 2)
        #expect(mapped == [
            "oauth:https://auth.example.com/.well-known/oauth-authorization-server",
            "oidc:https://auth.example.com/.well-known/openid-configuration",
        ])
    }

    @Test("buildDiscoveryUrls generates correct URLs for server with path")
    func buildDiscoveryUrlsWithPath() throws {
        let url = try #require(URL(string: "https://auth.example.com/tenant1"))
        let urls = buildDiscoveryUrls(authorizationServerUrl: url)

        let mapped = urls.map { entry in
            let type: String = switch entry.type {
            case .oauth: "oauth"
            case .oidc: "oidc"
            }
            return "\(type):\(entry.url.absoluteString)"
        }

        #expect(mapped.count == 4)
        #expect(mapped == [
            "oauth:https://auth.example.com/.well-known/oauth-authorization-server/tenant1",
            "oauth:https://auth.example.com/.well-known/oauth-authorization-server",
            "oidc:https://auth.example.com/.well-known/openid-configuration/tenant1",
            "oidc:https://auth.example.com/tenant1/.well-known/openid-configuration",
        ])
    }
}

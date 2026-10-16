import Foundation
import CryptoKit
import Testing
import AISDKProviderUtils
import AmazonBedrockProvider

@Suite("BedrockSigV4Fetch")
struct BedrockSigV4FetchTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private struct CredentialError: LocalizedError, Sendable {
        let message: String
        var errorDescription: String? { message }
    }

    private func httpResponse(for request: URLRequest) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/plain"]
        ))
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
    }

    private func sha256Hex(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    @Test("createSigV4FetchFunction bypasses signing for non-POST requests")
    func sigV4BypassesNonPost() async throws {
        let capture = RequestCapture()

        let underlyingFetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request)
            return FetchResponse(body: .data(Data()), urlResponse: http)
        }

        let fetch = createSigV4FetchFunction(
            getCredentials: { BedrockCredentials(region: "us-west-2", accessKeyId: "test", secretAccessKey: "secret") },
            fetch: underlyingFetch
        )

        var request = URLRequest(url: try #require(URL(string: "http://example.com")))
        request.httpMethod = "GET"
        request.httpBody = Data("payload".utf8)

        _ = try await fetch(request)

        guard let signed = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(signed)
        #expect(headers["authorization"] == nil)
        #expect(headers["x-amz-date"] == nil)
        #expect(headers["x-amz-content-sha256"] == nil)
        #expect(headers["user-agent"]?.contains("ai-sdk-amazon-bedrock/") == true)
    }

    @Test("createSigV4FetchFunction bypasses signing for POST requests without body")
    func sigV4BypassesPostWithoutBody() async throws {
        let capture = RequestCapture()

        let underlyingFetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request)
            return FetchResponse(body: .data(Data()), urlResponse: http)
        }

        let fetch = createSigV4FetchFunction(
            getCredentials: { BedrockCredentials(region: "us-west-2", accessKeyId: "test", secretAccessKey: "secret") },
            fetch: underlyingFetch
        )

        var request = URLRequest(url: try #require(URL(string: "http://example.com")))
        request.httpMethod = "POST"

        _ = try await fetch(request)

        guard let signed = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(signed)
        #expect(headers["authorization"] == nil)
        #expect(headers["x-amz-date"] == nil)
        #expect(headers["x-amz-content-sha256"] == nil)
    }

    @Test("createSigV4FetchFunction signs POST requests with body and merges headers")
    func sigV4SignsPostWithBody() async throws {
        let capture = RequestCapture()

        let underlyingFetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request)
            return FetchResponse(body: .data(Data()), urlResponse: http)
        }

        let fetch = createSigV4FetchFunction(
            getCredentials: {
                BedrockCredentials(
                    region: "us-west-2",
                    accessKeyId: "test-access-key",
                    secretAccessKey: "test-secret",
                    sessionToken: "test-session-token"
                )
            },
            fetch: underlyingFetch
        )

        let body = Data("{\"test\": \"data\"}".utf8)
        var request = URLRequest(url: try #require(URL(string: "http://example.com/path")))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("value", forHTTPHeaderField: "Custom-Header")

        _ = try await fetch(request)

        guard let signed = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(signed)
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-header"] == "value")
        #expect(headers["x-amz-security-token"] == "test-session-token")

        #expect(headers["x-amz-content-sha256"] == nil)

        #expect(headers["host"] == "example.com")

        let authorization = headers["authorization"]
        #expect(authorization?.hasPrefix("AWS4-HMAC-SHA256 Credential=test-access-key/") == true)
        #expect(authorization?.contains("SignedHeaders=") == true)
        #expect(authorization?.contains("Signature=") == true)

        if let date = headers["x-amz-date"] {
            #expect(date.count == 16)
            #expect(date.hasSuffix("Z"))
        } else {
            Issue.record("Expected x-amz-date header")
        }

        #expect(headers["user-agent"]?.contains("ai-sdk-amazon-bedrock/") == true)
    }

    @Test("createSigV4FetchFunction propagates credential provider errors and does not call fetch")
    func sigV4CredentialProviderFailure() async throws {
        let capture = RequestCapture()

        let underlyingFetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request)
            return FetchResponse(body: .data(Data()), urlResponse: http)
        }

        let fetch = createSigV4FetchFunction(
            getCredentials: { throw CredentialError(message: "Failed to get credentials") },
            fetch: underlyingFetch
        )

        var request = URLRequest(url: try #require(URL(string: "http://example.com")))
        request.httpMethod = "POST"
        request.httpBody = Data("payload".utf8)

        do {
            _ = try await fetch(request)
            Issue.record("Expected error")
        } catch {
            #expect(error.localizedDescription.contains("Failed to get credentials"))
        }

        #expect(await capture.current() == nil)
    }

    @Test("createApiKeyFetchFunction sets Bearer authorization and preserves other headers")
    func apiKeyFetchSetsAuthorization() async throws {
        let capture = RequestCapture()

        let underlyingFetch: FetchFunction = { request in
            await capture.store(request)
            let http = try httpResponse(for: request)
            return FetchResponse(body: .data(Data()), urlResponse: http)
        }

        let fetch = createApiKeyFetchFunction(apiKey: "test-api-key", fetch: underlyingFetch)

        let body = Data("{\"test\": \"data\"}".utf8)
        var request = URLRequest(url: try #require(URL(string: "http://example.com")))
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        _ = try await fetch(request)

        guard let signed = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(signed)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["user-agent"]?.contains("ai-sdk-amazon-bedrock/") == true)
    }

    @Test("SigV4 signature covers the double-encoded model path and service scope")
    func signatureMatchesWireRequest() async throws {
        let capture = RequestCapture()
        let fetch = createSigV4FetchFunction(getCredentials: { .init(region: "us-west-2", accessKeyId: "key", secretAccessKey: "secret") }, fetch: { request in
            await capture.store(request)
            return FetchResponse(body: .data(Data()), urlResponse: try httpResponse(for: request))
        }, service: "bedrock-mantle")
        var request = URLRequest(url: try #require(URL(string: "https://bedrock.test/model/arn%3Aaws%2Fprofile/invoke?z=2&a=1")))
        request.httpMethod = "POST"
        request.httpBody = Data("{}".utf8)
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue("café", forHTTPHeaderField: "x-unicode")
        _ = try await fetch(request)
        let signed = try #require(await capture.current())
        let date = try #require(signed.value(forHTTPHeaderField: "x-amz-date"))
        let scope = "\(date.prefix(8))/us-west-2/bedrock-mantle/aws4_request"
        let canonical = "POST\n/model/arn%253Aaws%252Fprofile/invoke\na=1&z=2\nhost:bedrock.test\nx-amz-date:\(date)\n\nhost;x-amz-date\n\(sha256Hex(Data("{}".utf8)))"
        let toSign = "AWS4-HMAC-SHA256\n\(date)\n\(scope)\n\(sha256Hex(Data(canonical.utf8)))"
        func hmac(_ key: Data, _ value: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(value.utf8), using: SymmetricKey(data: key))) }
        let key = hmac(hmac(hmac(hmac(Data("AWS4secret".utf8), String(date.prefix(8))), "us-west-2"), "bedrock-mantle"), "aws4_request")
        let signature = hmac(key, toSign).map { String(format: "%02x", $0) }.joined()
        #expect(signed.value(forHTTPHeaderField: "authorization") == "AWS4-HMAC-SHA256 Credential=key/\(scope), SignedHeaders=host;x-amz-date, Signature=\(signature)")
        #expect(signed.value(forHTTPHeaderField: "x-unicode") == "café")
    }
}

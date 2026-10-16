import Foundation
import Security
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("GoogleVertex auth")
struct GoogleVertexAuthTests {
    actor RequestCapture {
        private(set) var lastRequest: URLRequest?
        func capture(_ request: URLRequest) { lastRequest = request }
    }

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[pair.key.lowercased()] = pair.value
        }
    }

    private func okEmbeddingResponse(for url: URL) throws -> FetchResponse {
        let responseBody: [String: Any] = [
            "predictions": [
                [
                    "embeddings": [
                        "values": [0.1],
                        "statistics": ["token_count": 1]
                    ]
                ]
            ]
        ]

        let data = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])
        let response = try #require(HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        ))
        return FetchResponse(body: .data(data), urlResponse: response)
    }

    @Test("signs a fresh PKCS8 key from explicit credentials or an ADC file", arguments: [false, true])
    func signsFreshPKCS8Key(applicationCredentials: Bool) async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("vertex-service-account-\(UUID().uuidString).json")
        let original = ProcessInfo.processInfo.environment["GOOGLE_APPLICATION_CREDENTIALS"]
        if applicationCredentials { setenv("GOOGLE_APPLICATION_CREDENTIALS", file.path, 1) }
        defer {
            if applicationCredentials {
                if let original { setenv("GOOGLE_APPLICATION_CREDENTIALS", original, 1) }
                else { unsetenv("GOOGLE_APPLICATION_CREDENTIALS") }
                try? FileManager.default.removeItem(at: file)
            }
        }
        var keyError: Unmanaged<CFError>?
        let privateKey = try #require(SecKeyCreateRandomKey([
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ] as CFDictionary, &keyError))
        let privateData = try #require(SecKeyCopyExternalRepresentation(privateKey, &keyError)) as Data
        let publicKey = try #require(SecKeyCopyPublicKey(privateKey))
        let publicData = try #require(SecKeyCopyExternalRepresentation(publicKey, &keyError)) as Data
        func der(_ tag: UInt8, _ data: Data) -> Data {
            let length: [UInt8] = data.count < 128 ? [UInt8(data.count)] : [0x82, UInt8(data.count >> 8), UInt8(data.count & 0xff)]
            return Data([tag] + length) + data
        }
        let rsaAlgorithm = Data([0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00])
        let pkcs8 = der(0x30, Data([0x02, 0x01, 0x00]) + rsaAlgorithm + der(0x04, privateData))
        let pem = "-----BEGIN PRIVATE KEY-----\\n\(pkcs8.base64EncodedString())\\n-----END PRIVATE KEY-----"
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: applicationCredentials ? "global" : nil, project: applicationCredentials ? "project" : nil, fetch: { request in
            await requests.append(request)
            if request.url?.absoluteString == "https://oauth2.googleapis.com/token" {
                let form = String(decoding: try #require(request.httpBody), as: UTF8.self)
                let fields = URLComponents(string: "https://oauth.example/?\(form)")?.queryItems
                #expect(fields?.first(where: { $0.name == "grant_type" })?.value == "urn:ietf:params:oauth:grant-type:jwt-bearer")
                let jwt = try #require(fields?.first(where: { $0.name == "assertion" })?.value)
                let parts = jwt.split(separator: ".").map(String.init)
                #expect(parts.count == 3)
                func decode(_ string: String) throws -> Data {
                    let base64 = string.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
                    return try #require(Data(base64Encoded: base64 + String(repeating: "=", count: (4 - base64.count % 4) % 4)))
                }
                let header = try JSONDecoder().decode(JSONObject.self, from: decode(parts[0]))
                let claims = try JSONDecoder().decode(JSONObject.self, from: decode(parts[1]))
                #expect(header["alg"] == .string("RS256"))
                #expect(header["kid"] == .string("fresh-key"))
                #expect(claims["iss"] == .string("account@example.com"))
                #expect(claims["aud"] == .string("https://oauth2.googleapis.com/token"))
                #expect(claims["scope"] == .string("https://www.googleapis.com/auth/cloud-platform"))
                guard case .number(let issued) = claims["iat"], case .number(let expires) = claims["exp"] else {
                    Issue.record("Missing JWT timestamps"); throw CancellationError()
                }
                #expect(expires - issued == 3600)
                var verificationError: Unmanaged<CFError>?
                let verificationKey = try #require(SecKeyCreateWithData(publicData as CFData, [
                    kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
                    kSecAttrKeyClass as String: kSecAttrKeyClassPublic
                ] as CFDictionary, &verificationError))
                #expect(SecKeyVerifySignature(verificationKey, .rsaSignatureMessagePKCS1v15SHA256,
                    Data("\(parts[0]).\(parts[1])".utf8) as CFData, try decode(parts[2]) as CFData, &verificationError))
                return try vertexResponse(request, #"{"access_token":"signed-token","expires_in":3600}"#)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer signed-token")
            return try vertexResponse(request, #"{"embedding":{"values":[0.5]}}"#)
        }, baseURL: applicationCredentials ? nil : "https://custom.example", googleCredentials: applicationCredentials ? nil : .init(clientEmail: "account@example.com", privateKey: pem, privateKeyId: "fresh-key")))
        if applicationCredentials {
            let account: JSONObject = ["type": .string("service_account"), "client_email": .string("account@example.com"), "private_key": .string(pem), "private_key_id": .string("fresh-key")]
            try JSONEncoder().encode(account).write(to: file, options: .atomic)
        }
        let result = try await provider.embeddingModel(modelId: "gemini-embedding-2").doEmbed(options: .init(values: ["hello"]))
        #expect(result.embeddings == [[0.5]])
        #expect(await requests.last?.url?.host == (applicationCredentials ? "aiplatform.googleapis.com" : "custom.example"))
    }

    @Test("injects Authorization bearer token when apiKey is absent and baseURL is not provided")
    func injectsBearerToken() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)
            return try okEmbeddingResponse(for: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            fetch: fetch,
            accessTokenProvider: { "test-access-token" }
        ))

        let model = try provider.embeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: .init(values: ["hello"]))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer test-access-token")
    }

    @Test("resolves async headers per request and preserves request overrides")
    func asyncHeaders() async throws {
        actor Tokens {
            var value = 0
            func headers() -> [String: String?] { value += 1; return ["Authorization": "Bearer dynamic-\(value)", "x-priority": "provider"] }
        }
        let tokens = Tokens()
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: "global", project: "project", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"embedding":{"values":[0.5]}}"#)
        }, headersProvider: { await tokens.headers() }))
        let model = try provider.embeddingModel(modelId: "gemini-embedding-2")
        for _ in 0..<2 {
            let result = try await model.doEmbed(options: .init(values: ["hello"], headers: ["X-Priority": "request", "user-agent": "client"]))
            #expect(result.embeddings == [[0.5]])
        }
        let captured = await requests.values
        #expect(captured.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer dynamic-1", "Bearer dynamic-2"])
        #expect(captured.last?.value(forHTTPHeaderField: "x-priority") == "request")
        let userAgent = try #require(captured.last?.value(forHTTPHeaderField: "user-agent"))
        #expect(userAgent.hasPrefix("client "))
        #expect(userAgent.contains("ai-sdk-google-vertex/\(GOOGLE_VERTEX_VERSION)"))
    }

    @Test("does not override Authorization when provided via headers")
    func doesNotOverrideAuthorizationHeader() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.capture(request)
            return try okEmbeddingResponse(for: try #require(request.url))
        }

        let provider = createGoogleVertex(settings: GoogleVertexProviderSettings(
            location: "us-central1",
            project: "test-project",
            headers: ["Authorization": "Bearer custom"],
            fetch: fetch,
            accessTokenProvider: { "test-access-token" }
        ))

        let model = try provider.embeddingModel(modelId: "text-embedding-004")
        _ = try await model.doEmbed(options: .init(values: ["hello"]))

        let request = try #require(await capture.lastRequest)
        let headers = normalizedHeaders(request)
        #expect(headers["authorization"] == "Bearer custom")
    }

    @Test("custom baseURL without explicit credentials leaves authentication to the gateway")
    func customBaseURLSkipsOAuthInjection() async throws {
        let capture = RequestCapture()
        let provider = createGoogleVertex(settings: .init(fetch: { request in
            await capture.capture(request)
            return try okEmbeddingResponse(for: try #require(request.url))
        }, baseURL: "https://custom-endpoint.example.com"))
        let result = try await provider.embeddingModel(modelId: "text-embedding-004").doEmbed(options: .init(values: ["hello"]))
        #expect(result.embeddings == [[0.1]])
        let request = try #require(await capture.lastRequest)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }
}


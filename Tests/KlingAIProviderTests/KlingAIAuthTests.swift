import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import KlingAIProvider

@Suite("generateKlingAIAuthToken", .serialized)
struct KlingAIAuthTests {
    private func decodeBase64URL(_ value: String) throws -> Data {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        let remainder = base64.count % 4
        if remainder != 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }

        guard let data = Data(base64Encoded: base64) else {
            struct DecodeError: Error {}
            throw DecodeError()
        }
        return data
    }

    private func decodeJSONObject(_ data: Data) throws -> [String: Any] {
        let obj = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dict = obj as? [String: Any] else {
            struct DecodeError: Error {}
            throw DecodeError()
        }
        return dict
    }

    private func withCleanEnv(_ body: () async throws -> Void) async throws {
        let originalAPIKey = ProcessInfo.processInfo.environment["KLINGAI_API_KEY"]
        let originalAK = ProcessInfo.processInfo.environment["KLINGAI_ACCESS_KEY"]
        let originalSK = ProcessInfo.processInfo.environment["KLINGAI_SECRET_KEY"]

        defer {
            if let originalAPIKey { setenv("KLINGAI_API_KEY", originalAPIKey, 1) } else { unsetenv("KLINGAI_API_KEY") }
            if let originalAK {
                setenv("KLINGAI_ACCESS_KEY", originalAK, 1)
            } else {
                unsetenv("KLINGAI_ACCESS_KEY")
            }

            if let originalSK {
                setenv("KLINGAI_SECRET_KEY", originalSK, 1)
            } else {
                unsetenv("KLINGAI_SECRET_KEY")
            }
        }

        unsetenv("KLINGAI_API_KEY")
        unsetenv("KLINGAI_ACCESS_KEY")
        unsetenv("KLINGAI_SECRET_KEY")

        try await body()
    }

    @Test("should generate a valid JWT token structure")
    func tokenStructure() async throws {
        try await withCleanEnv {
            let token = try await generateKlingAIAuthToken(
                accessKey: "test-access-key",
                secretKey: "test-secret-key"
            )

            let parts = token.split(separator: ".")
            #expect(parts.count == 3)
        }
    }

    @Test("should include correct header with HS256 algorithm")
    func headerHS256() async throws {
        try await withCleanEnv {
            let token = try await generateKlingAIAuthToken(
                accessKey: "test-access-key",
                secretKey: "test-secret-key"
            )

            let parts = token.split(separator: ".")
            let headerData = try decodeBase64URL(String(parts[0]))
            let header = try decodeJSONObject(headerData)

            #expect(header["alg"] as? String == "HS256")
            #expect(header["typ"] as? String == "JWT")
        }
    }

    @Test("should include issuer (iss) matching the access key")
    func payloadIssuer() async throws {
        try await withCleanEnv {
            let token = try await generateKlingAIAuthToken(
                accessKey: "my-access-key-123",
                secretKey: "my-secret-key"
            )

            let parts = token.split(separator: ".")
            let payloadData = try decodeBase64URL(String(parts[1]))
            let payload = try decodeJSONObject(payloadData)

            #expect(payload["iss"] as? String == "my-access-key-123")
        }
    }

    @Test("should include exp and nbf claims")
    func payloadExpAndNbf() async throws {
        try await withCleanEnv {
            let token = try await generateKlingAIAuthToken(accessKey: "test-ak", secretKey: "test-sk")

            let parts = token.split(separator: ".")
            let payloadData = try decodeBase64URL(String(parts[1]))
            let payload = try decodeJSONObject(payloadData)

            let exp = (payload["exp"] as? NSNumber)?.doubleValue
            let nbf = (payload["nbf"] as? NSNumber)?.doubleValue

            #expect(exp != nil)
            #expect(nbf != nil)

            if let exp, let nbf {
                // Upstream: exp = now + 1800, nbf = now - 5
                let diff = exp - nbf
                #expect(diff > 1800 - 10)
                #expect(diff < 1800 + 10)
            }
        }
    }

    @Test("should load access key from environment variable")
    func loadAccessKeyFromEnv() async throws {
        try await withCleanEnv {
            setenv("KLINGAI_ACCESS_KEY", "env-access-key", 1)

            let token = try await generateKlingAIAuthToken(secretKey: "test-sk")
            let parts = token.split(separator: ".")
            let payloadData = try decodeBase64URL(String(parts[1]))
            let payload = try decodeJSONObject(payloadData)

            #expect(payload["iss"] as? String == "env-access-key")
        }
    }

    @Test("should prefer explicit accessKey over environment variable")
    func explicitAccessKeyWins() async throws {
        try await withCleanEnv {
            setenv("KLINGAI_ACCESS_KEY", "env-access-key", 1)

            let token = try await generateKlingAIAuthToken(accessKey: "explicit-access-key", secretKey: "test-sk")
            let parts = token.split(separator: ".")
            let payloadData = try decodeBase64URL(String(parts[1]))
            let payload = try decodeJSONObject(payloadData)

            #expect(payload["iss"] as? String == "explicit-access-key")
        }
    }

    @Test("should throw when access key is not available")
    func missingAccessKeyThrows() async throws {
        try await withCleanEnv {
            do {
                _ = try await generateKlingAIAuthToken(secretKey: "test-sk")
                Issue.record("Expected error")
            } catch let error as LoadSettingError {
                #expect(error.message.contains("KlingAI access key"))
            }
        }
    }

    @Test("should throw when secret key is not available")
    func missingSecretKeyThrows() async throws {
        try await withCleanEnv {
            do {
                _ = try await generateKlingAIAuthToken(accessKey: "test-ak")
                Issue.record("Expected error")
            } catch let error as LoadSettingError {
                #expect(error.message.contains("KlingAI secret key"))
            }
        }
    }

    @Test("provider auth prefers explicit credentials before environment defaults", arguments: ["api", "pair", "environment", "environment-pair", "missing"])
    func providerAuth(_ source: String) async throws {
        try await withCleanEnv {
            if source != "missing" { setenv("KLINGAI_API_KEY", source == "environment-pair" ? "  " : " environment-key ", 1) }
            if source == "environment-pair" {
                setenv("KLINGAI_ACCESS_KEY", "environment-access", 1)
                setenv("KLINGAI_SECRET_KEY", "environment-secret", 1)
            }
            let fetch: FetchFunction = { request in
                let authorization = try #require(request.value(forHTTPHeaderField: "Authorization"))
                if source == "api" { #expect(authorization == "Bearer explicit-key") }
                else if source == "environment" { #expect(authorization == "Bearer environment-key") }
                else {
                    let token = String(authorization.dropFirst("Bearer ".count))
                    let pieces = token.split(separator: ".")
                    let payload = try decodeJSONObject(decodeBase64URL(String(pieces[1])))
                    #expect(payload["iss"] as? String == (source == "pair" ? "explicit-access" : "environment-access"))
                }
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
                return FetchResponse(body: .data(Data(#"{"code":0,"message":"success","data":{"task_id":"task"}}"#.utf8)), urlResponse: response)
            }
            let provider = createKlingAI(settings: .init(apiKey: source == "api" ? " explicit-key " : nil, accessKey: source == "pair" || source == "api" ? "explicit-access" : nil, secretKey: source == "pair" || source == "api" ? "explicit-secret" : nil, fetch: fetch))
            if source == "missing" {
                await #expect(throws: LoadAPIKeyError.self) { try await provider.video(.klingV30T2v).doStart(options: .init(n: 1)) }
            } else {
                let result = try await provider.video(.klingV30T2v).doStart(options: .init(n: 1))
                #expect(result.operation == .object(["taskId": .string("task"), "endpointPath": .string("/v1/videos/text2video")]))
            }
        }
    }

    @Test("should produce different tokens for different secret keys")
    func differentSecretsProduceDifferentSignatures() async throws {
        try await withCleanEnv {
            let token1 = try await generateKlingAIAuthToken(accessKey: "same-ak", secretKey: "secret-key-1")
            let token2 = try await generateKlingAIAuthToken(accessKey: "same-ak", secretKey: "secret-key-2")

            let sig1 = token1.split(separator: ".")[2]
            let sig2 = token2.split(separator: ".")[2]
            #expect(sig1 != sig2)
        }
    }
}

import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import HumeProvider

actor HumeEndpoint {
    private var request: URLRequest?
    let status: Int
    let data: Data
    init(error: Bool = false) throws {
        status = error ? 400 : 200
        data = error ? try JSONEncoder().encode(JSONValue.object(["error": ["message": "bad voice", "code": 1e100]])) : Data([1, 2, 3])
    }
    func fetch(_ request: URLRequest) -> FetchResponse {
        self.request = request
        return .init(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: [:])!)
    }
    func sent() throws -> URLRequest { try #require(request) }
    func body() throws -> JSONObject { try JSONDecoder().decode(JSONObject.self, from: #require(try sent().httpBody)) }
}

@Suite("Hume speech public contracts")
struct HumeProviderTests {
    @Test("speech synthesizes binary audio with defaults and lazy request-only headers")
    func generation() async throws {
        let endpoint = try HumeEndpoint()
        let provider = createHume(settings: .init(apiKey: "key", headers: ["x-hume-api-key": "provider"], fetch: { await endpoint.fetch($0) }))
        let result = try await provider().speech.doGenerate(options: .init(text: "Hello", instructions: "calm", speed: 1.25, headers: ["X-Hume-Api-Key": "caller"]))
        #expect(result.audio == .binary(Data([1, 2, 3])))
        #expect(result.response.modelId == "")
        #expect(try await endpoint.body() == ["utterances": [["text": "Hello", "description": "calm", "speed": 1.25, "voice": ["id": "d8ab67c6-953d-4bd8-9370-8fa53a0f1453", "provider": "HUME_AI"]]], "format": ["type": "mp3"]])
        let request = try await endpoint.sent()
        #expect(request.url?.absoluteString == "https://api.hume.ai/v0/tts/file")
        #expect(request.value(forHTTPHeaderField: "X-Hume-Api-Key") == "caller")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-hume/") == true)
        let recorded = try #require(result.request?.body as? String)
        let sent = try await endpoint.body()
        #expect(try JSONDecoder().decode(JSONObject.self, from: Data(recorded.utf8)) == sent)
    }

    @Test("context object unions prefer generation IDs and map utterance voice/silence fields", arguments: [false, true])
    func context(generationId: Bool) async throws {
        let endpoint = try HumeEndpoint()
        let context: JSONValue = generationId ? ["generationId": "previous", "utterances": "ignored"] : ["utterances": [["text": "Before", "description": "warm", "trailingSilence": 0.5, "voice": ["name": "Voice", "provider": "CUSTOM_VOICE"], "unknown": true]]]
        let result = try await createHume(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech().doGenerate(options: .init(text: "Hello", voice: "voice", outputFormat: "wav", providerOptions: ["hume": ["context": context]]))
        let body = try await endpoint.body()
        #expect(body["context"] == (generationId ? ["generation_id": "previous"] : ["utterances": [["text": "Before", "description": "warm", "trailing_silence": 0.5, "voice": ["name": "Voice", "provider": "CUSTOM_VOICE"]]]]))
        #expect(body["format"] == ["type": "wav"])
        #expect(result.warnings.isEmpty)
    }

    @Test("invalid known context fields fail rather than leaking null or unknown provider values", arguments: [JSONValue.object([:]), .object(["utterances": [["text": "Before", "description": .null]]]), .object(["utterances": [["text": "Before", "voice": ["id": "voice", "provider": "other"]]]])])
    func invalidContext(context: JSONValue) async throws {
        let model = createHume().speech()
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(text: "Hello", providerOptions: ["hume": ["context": context]])) }
    }

    @Test("unsupported format falls back while unsupported language is reported")
    func warnings() async throws {
        let endpoint = try HumeEndpoint()
        let result = try await createHume(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech().doGenerate(options: .init(text: "Hello", outputFormat: "FLAC", language: "auto"))
        #expect(try await endpoint.body()["format"] == ["type": "mp3"])
        #expect(result.warnings.compactMap { if case .unsupported(let feature, _) = $0 { feature } else { nil } } == ["outputFormat", "language"])
    }

    @Test("large numeric API errors remain recognized provider failures")
    func apiError() async throws {
        let endpoint = try HumeEndpoint(error: true)
        let model = createHume(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).speech()
        do {
            _ = try await model.doGenerate(options: .init(text: "Hello"))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.message == "bad voice")
        }
    }

    @Suite("lazy auth", .serialized)
    struct Authentication {
        @Test("missing key surfaces only from speech synthesis")
        func missingKey() async throws {
            let original = getenv("HUME_API_KEY").flatMap { String(validatingCString: $0) }
            unsetenv("HUME_API_KEY")
            defer { if let original { setenv("HUME_API_KEY", original, 1) } else { unsetenv("HUME_API_KEY") } }
            let model = createHume().speech()
            await #expect(throws: LoadAPIKeyError.self) { try await model.doGenerate(options: .init(text: "Hello")) }
        }
    }
}

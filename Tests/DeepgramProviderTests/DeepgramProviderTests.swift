import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import DeepgramProvider

actor AudioEndpoint {
    private var request: URLRequest?
    let data: Data
    let status: Int
    let headers: [String: String]
    init(json: JSONValue, status: Int = 200) throws {
        data = try JSONEncoder().encode(json)
        self.status = status
        headers = ["Content-Type": "application/json"]
    }
    init(audio: Data, headers: [String: String] = [:]) {
        data = audio
        status = 200
        self.headers = headers
    }
    func fetch(_ request: URLRequest) -> FetchResponse {
        self.request = request
        return .init(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!)
    }
    func sent() throws -> URLRequest { try #require(request) }
    func query() throws -> [String: String] {
        let request = try sent()
        let url = try #require(request.url)
        var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%20")
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}

@Suite("Deepgram transcription public contracts")
struct DeepgramProviderTests {
    @Test("transcription sends raw audio without implicit diarization and preserves detected language and seconds")
    func transcription() async throws {
        let endpoint = try AudioEndpoint(json: ["metadata": ["duration": 1.25], "results": ["channels": [["detected_language": "fr", "alternatives": [["transcript": "Bonjour", "words": [["word": "Bonjour", "start": 0.1, "end": 1.2]]]]]]]])
        let provider = createDeepgram(settings: .init(apiKey: "key", headers: ["authorization": "provider"], fetch: { await endpoint.fetch($0) }))
        let result = try await provider(.nova3).transcription.doGenerate(options: .init(audio: .base64("AQI="), mediaType: "audio/wav", headers: ["authorization": "caller"]))
        #expect(result.text == "Bonjour")
        #expect(result.segments == [.init(text: "Bonjour", startSecond: 0.1, endSecond: 1.2)])
        #expect(result.language == "fr")
        #expect(result.durationInSeconds == 1.25)
        #expect(result.usage == ["seconds": 1.25])
        #expect(try await endpoint.query() == ["model": "nova-3"])
        let request = try await endpoint.sent()
        #expect(request.httpBody == Data([1, 2]))
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "audio/wav")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "caller")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-deepgram/") == true)
    }

    @Test("transcription options use form query encoding, false and nullish semantics")
    func transcriptionOptions() async throws {
        let endpoint = try AudioEndpoint(json: [:])
        let result = try await createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).transcription(modelId: .nova3).doGenerate(options: .init(
            audio: .binary(Data()), mediaType: "audio/mpeg", providerOptions: ["deepgram": ["detectLanguage": true, "diarize": false, "redact": ["pii", "a+b"], "summarize": false, "uttSplit": 1e100, "keyterm": "C++ a&b~", "language": .null]]))
        #expect(try await endpoint.query() == ["model": "nova-3", "detect_language": "true", "diarize": "false", "redact": "pii,a+b", "summarize": "false", "utt_split": "1e+100", "keyterm": "C++ a&b~"])
        #expect(try await endpoint.sent().url?.absoluteString.contains("keyterm=C%2B%2B+a%26b%7E") == true)
        #expect(result.text.isEmpty && result.segments.isEmpty && result.usage == nil)
    }

    @Test("malformed transcript words fail at the HTTP schema boundary")
    func responseSchema() async throws {
        let endpoint = try AudioEndpoint(json: ["results": ["channels": [["alternatives": [["transcript": "missing words"]]]]]])
        let model = createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).transcription(modelId: .nova3)
        await #expect(throws: APICallError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav")) }
    }

    @Test("Deepgram API error fields remain available on a failed public call")
    func apiError() async throws {
        let endpoint = try AudioEndpoint(json: ["err_code": "INVALID_QUERY_PARAMETER", "err_msg": "bad model", "request_id": "request"], status: 400)
        let model = createDeepgram(settings: .init(apiKey: "key", fetch: { await endpoint.fetch($0) })).transcription(modelId: .nova3)
        do {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 400)
            #expect(error.message == "bad model")
            #expect((error.data as? DeepgramErrorData)?.errCode == "INVALID_QUERY_PARAMETER")
        }
    }

    @Suite("lazy authentication", .serialized)
    struct Authentication {
        @Test("missing key surfaces from the request")
        func missingKey() async throws {
            let original = getenv("DEEPGRAM_API_KEY").flatMap { String(validatingCString: $0) }
            unsetenv("DEEPGRAM_API_KEY")
            defer { if let original { setenv("DEEPGRAM_API_KEY", original, 1) } else { unsetenv("DEEPGRAM_API_KEY") } }
            let model = createDeepgram().transcription(modelId: .nova3)
            await #expect(throws: LoadAPIKeyError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav")) }
        }
    }
}

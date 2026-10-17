import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GladiaProvider

actor GladiaEndpoint {
    let resultURL: String
    let result: JSONValue
    private var requests: [URLRequest] = []
    private var pending: Bool
    init(_ result: JSONValue, resultURL: String = "https://api.gladia.io/v2/result/job", pending: Bool = false) {
        self.result = result; self.resultURL = resultURL; self.pending = pending
    }
    func fetch(_ request: URLRequest) throws -> FetchResponse {
        requests.append(request)
        let body: JSONValue
        switch request.url!.path {
        case "/v2/upload": body = ["audio_url": "https://storage.example/audio"]
        case "/v2/pre-recorded": body = ["result_url": .string(resultURL)]
        default:
            if pending { pending = false; body = ["status": "processing"] }
            else { body = result }
        }
        return .init(body: .data(try JSONEncoder().encode(body)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
    }
    func request(path: String) throws -> URLRequest { try #require(requests.first { $0.url?.path == path }) }
    func payload() throws -> JSONObject { try JSONDecoder().decode(JSONObject.self, from: #require(try request(path: "/v2/pre-recorded").httpBody)) }
}

private let completedResult: JSONValue = ["status": "done", "future": true, "result": ["metadata": ["audio_duration": 2.5, "unknown": true], "transcription": ["full_transcript": "Hello", "languages": ["en"], "utterances": [["start": 0.25, "end": 2.5, "text": "Hello", "speaker": .null, "confidence": 0.9, "words": [["word": "Hello", "start": 0.25, "end": 2.5, "confidence": .null, "future": true]], "unknown": true]]]]]

@Suite("Gladia file transcription contracts")
struct GladiaProviderTests {
    @Test("upload/init/poll returns parsed metadata and sends credentials only to its API origin", arguments: [false, true])
    func transcription(externalResult: Bool) async throws {
        let url = externalResult ? "https://8.8.8.8/result" : "https://api.gladia.io/v2/result/job"
        let endpoint = GladiaEndpoint(completedResult, resultURL: url, pending: !externalResult)
        let provider = createGladia(settings: .init(apiKey: "key", headers: ["x-gladia-key": "provider"], fetch: { try await endpoint.fetch($0) }))
        let model = try #require(provider.transcriptionModel(modelId: "ignored"))
        let result = try await model.doGenerate(options: .init(audio: .base64("AQI="), mediaType: "audio/mpeg", providerOptions: ["gladia": [
            "customVocabulary": [1, ["camelCase": true], .null], "customVocabularyConfig": ["vocabulary": [["value": "AI", "intensity": 1.5, "unknown": true]], "defaultIntensity": 0.25],
            "subtitlesConfig": ["maximumRowsPerCaption": 1.5], "diarizationConfig": ["numberOfSpeakers": 2.5], "codeSwitchingConfig": [:],
            "customSpellingConfig": ["spellingDictionary": ["AI": ["A I"]]], "customMetadata": ["camelCase": ["keepThis": true]]
        ]], headers: ["X-Gladia-Key": "caller", "X-Caller": "private"]))
        #expect(result.text == "Hello")
        #expect(result.segments == [.init(text: "Hello", startSecond: 0.25, endSecond: 2.5)])
        #expect(result.language == "en" && result.durationInSeconds == 2.5)
        #expect(result.response.body == nil)
        #expect(result.providerMetadata?["gladia"] == ["status": "done", "result": ["metadata": ["audio_duration": 2.5], "transcription": ["full_transcript": "Hello", "languages": ["en"], "utterances": [["start": 0.25, "end": 2.5, "text": "Hello", "speaker": .null, "confidence": 0.9, "words": [["word": "Hello", "start": 0.25, "end": 2.5, "confidence": .null]]]]]]])
        let sent = try await endpoint.payload()
        #expect(sent["custom_vocabulary"] == [1, ["camelCase": true], .null])
        #expect(sent["custom_vocabulary_config"] == ["vocabulary": [["value": "AI", "intensity": 1.5]], "default_intensity": 0.25])
        #expect(sent["subtitles_config"] == ["maximum_rows_per_caption": 1.5])
        #expect(sent["diarization_config"] == ["number_of_speakers": 2.5])
        #expect(sent["code_switching_config"] == [:])
        #expect(sent["custom_spelling_config"] == ["spelling_dictionary": ["AI": ["A I"]]])
        #expect(sent["custom_metadata"] == ["camelCase": ["keepThis": true]])
        let upload = try await endpoint.request(path: "/v2/upload")
        #expect(String(decoding: upload.httpBody ?? Data(), as: UTF8.self).contains("filename=\"audio.mp3\""))
        #expect(upload.value(forHTTPHeaderField: "X-Gladia-Key") == "caller")
        let polled = try await endpoint.request(path: externalResult ? "/result" : "/v2/result/job")
        let headers = Dictionary(uniqueKeysWithValues: (polled.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) })
        if externalResult {
            #expect(Set(headers.keys) == ["user-agent"])
            #expect(headers["user-agent"]?.contains("ai-sdk-provider-utils/") == true)
        } else {
            #expect(headers["x-gladia-key"] == "caller")
            #expect(headers["x-caller"] == "private")
        }
    }

    @Test("terminal error and empty result expose the upstream named failures", arguments: ["error", "done"])
    func jobFailure(status: String) async throws {
        let endpoint = GladiaEndpoint(["status": .string(status)])
        let model = createGladia(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription()
        do {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
            Issue.record("Expected job failure")
        } catch let error as any AISDKError {
            #expect(error.name == (status == "error" ? "TranscriptionJobFailed" : "TranscriptionResultEmpty"))
            #expect(hasMarker(error, marker: "vercel.ai.error"))
            #expect((error.cause as? InvalidResponseDataError)?.data as? JSONObject == ["status": .string(status)])
        }
    }

    @Test("known vocabulary config shapes remain validated")
    func invalidOptions() async throws {
        let endpoint = GladiaEndpoint(completedResult)
        let model = createGladia(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription()
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["gladia": ["customVocabularyConfig": ["vocabulary": [true]]]])) }
    }

    @Suite("lazy auth", .serialized)
    struct Authentication {
        @Test("missing key fails only when transcription is requested")
        func missingKey() async throws {
            let original = getenv("GLADIA_API_KEY").flatMap { String(validatingCString: $0) }
            unsetenv("GLADIA_API_KEY")
            defer { if let original { setenv("GLADIA_API_KEY", original, 1) } else { unsetenv("GLADIA_API_KEY") } }
            let model = createGladia().transcription()
            await #expect(throws: LoadAPIKeyError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav")) }
        }
    }
}

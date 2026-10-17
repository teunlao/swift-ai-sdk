import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AssemblyAIProvider

actor TranscriptEndpoint {
    private var requests: [URLRequest] = []
    private var pending: Bool
    let transcript: JSONValue
    let finalStatus: Int
    init(_ transcript: JSONValue, pending: Bool = false, finalStatus: Int = 200) {
        self.transcript = transcript; self.pending = pending; self.finalStatus = finalStatus
    }
    func fetch(_ request: URLRequest) throws -> FetchResponse {
        requests.append(request)
        let path = request.url!.path
        let body: JSONValue
        var status = 200
        switch path {
        case "/v2/upload": body = ["upload_url": "https://storage.example/audio"]
        case "/v2/transcript": body = ["id": "job", "status": "queued"]
        default:
            if pending { pending = false; body = ["id": "job", "status": "processing"] }
            else { body = transcript; status = finalStatus }
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Stage": path])!
        return .init(body: .data(try JSONEncoder().encode(body)), urlResponse: response)
    }
    func request(path: String) throws -> URLRequest { try #require(requests.first { $0.url?.path == path }) }
    func payload() throws -> JSONObject { try JSONDecoder().decode(JSONObject.self, from: #require(try request(path: "/v2/transcript").httpBody)) }
}

@Suite("AssemblyAI transcription public contracts")
struct AssemblyAITranscriptionModelTests {
    @Test("polling uses caller fetch, converts word milliseconds and retains raw diarization metadata")
    func transcript() async throws {
        let utterances: JSONValue = [["start": 1250, "end": 2500, "text": "Hello", "speaker": "A", "words": [["start": 1250, "end": 2500, "text": "Hello", "speaker": "A", "vendor": true]], "future": true]]
        let endpoint = TranscriptEndpoint(["id": "job", "status": "completed", "text": "Hello", "language_code": "en", "words": [["start": 1250, "end": 2500, "text": "Hello"]], "utterances": utterances, "entities": [["entity_type": "person", "text": "A", "extra": 1]], "iab_categories_result": ["status": "success", "future": true]], pending: true)
        let model = createAssemblyAI(settings: .init(apiKey: "key", headers: ["authorization": "provider"], fetch: { try await endpoint.fetch($0) }))(.universal35Pro).transcription
        let result = try await model.doGenerate(options: .init(audio: .base64("AQI="), mediaType: "audio/wav", headers: ["authorization": "caller"]))
        #expect(result.text == "Hello")
        #expect(result.segments == [.init(text: "Hello", startSecond: 1.25, endSecond: 2.5)])
        #expect(result.durationInSeconds == 2.5)
        #expect(result.language == "en")
        #expect(result.providerMetadata?["assemblyai"]?["utterances"] == utterances)
        #expect(result.providerMetadata?["assemblyai"]?["entities"] == [["entity_type": "person", "text": "A", "extra": 1]])
        #expect(result.response.headers?["x-stage"] == "/v2/transcript/job")
        let upload = try await endpoint.request(path: "/v2/upload")
        #expect(upload.httpBody == Data([1, 2]))
        #expect(upload.value(forHTTPHeaderField: "Authorization") == "caller")
        #expect(upload.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-assemblyai/") == true)
        #expect(try await endpoint.request(path: "/v2/transcript/job").value(forHTTPHeaderField: "Authorization") == "caller")
        #expect(try await endpoint.payload() == ["audio_url": "https://storage.example/audio", "speech_models": ["universal-3-5-pro"]])
    }

    @Test("nested options map to wire keys without changing dictionary labels, preserving explicit zero duration")
    func options() async throws {
        let endpoint = TranscriptEndpoint(["id": "job", "status": "completed", "audio_duration": 0, "words": [["start": 1000, "end": 2000, "text": "x"]]])
        let result = try await createAssemblyAI(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription(modelId: .universal35Pro).doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["assemblyai": [
            "keytermsPrompt": ["Bearclaw"], "prompt": "medical", "domain": "medical-v1", "temperature": 0.25, "removeAudioTags": "speaker",
            "speakerOptions": ["minSpeakersExpected": 1, "maxSpeakersExpected": 3],
            "languageDetectionOptions": ["expectedLanguages": ["en", "es"], "codeSwitching": false, "codeSwitchingConfidenceThreshold": 0.5],
            "redactPii": true, "redactStaticEntities": ["INTERNAL_TOOL": ["Bearclaw"]], "redactPiiAudio": true,
            "redactPiiAudioOptions": ["returnRedactedNoSpeechAudio": false, "overrideAudioRedactionMethod": "silence"], "wordBoost": ["word"], "boostParam": "high", "languageCode": .null
        ]]))
        let body = try await endpoint.payload()
        #expect(body["speaker_options"] == ["min_speakers_expected": 1, "max_speakers_expected": 3])
        #expect(body["language_detection_options"] == ["expected_languages": ["en", "es"], "code_switching": false, "code_switching_confidence_threshold": 0.5])
        #expect(body["redact_static_entities"] == ["INTERNAL_TOOL": ["Bearclaw"]])
        #expect(body["redact_pii_audio_options"] == ["return_redacted_no_speech_audio": false, "override_audio_redaction_method": "silence"])
        #expect(body["language_code"] == nil)
        #expect(body["keyterms_prompt"] == ["Bearclaw"])
        #expect(result.durationInSeconds == 0)
        #expect(result.warnings.contains { if case .deprecated(let setting, _) = $0 { setting == "wordBoost, boostParam" } else { false } })
    }

    @Test("source best-model routing and prerequisite warnings remain visible")
    func warnings() async throws {
        let endpoint = TranscriptEndpoint(["id": "job", "status": "completed"])
        let result = try await createAssemblyAI(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription(modelId: .best).doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["assemblyai": ["redactPiiReturnUnredacted": false, "redactPiiAudioOptions": [:], "languageCode": "en", "languageDetection": true]]))
        #expect(try await endpoint.payload()["speech_model"] == "best")
        #expect(try await endpoint.payload()["speech_models"] == nil)
        #expect(result.warnings.filter { if case .other = $0 { true } else { false } }.count == 3)
        #expect(result.warnings.contains { if case .deprecated = $0 { true } else { false } })
    }

    @Test("unsafe integers and bounded nested options fail through the public operation", arguments: [JSONValue.object(["audioEndAt": 1e100]), .object(["languageDetectionOptions": ["codeSwitchingConfidenceThreshold": 1.1]])])
    func invalidOptions(options: JSONValue) async throws {
        let endpoint = TranscriptEndpoint(["id": "job", "status": "completed"])
        let model = createAssemblyAI(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription(modelId: .universal35Pro)
        guard case .object(let values) = options else { Issue.record("Expected options object"); return }
        await #expect(throws: InvalidArgumentError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", providerOptions: ["assemblyai": values])) }
    }
}

import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import ElevenLabsProvider

@Suite("ElevenLabs public contracts")
struct ElevenLabsProviderTests {
    @Test("speech encodes options and preserves binary response")
    func speechRequestAndResponse() async throws {
        let bytes = Data([1, 2, 3])
        let provider = createElevenLabs(settings: .init(
            apiKey: "provider-key",
            headers: ["Authorization": "provider", "XI-API-KEY": "custom-key", "User-Agent": "client"],
            fetch: { request in
                #expect(request.url?.path == "/v1/text-to-speech/voice")
                let query = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems
                #expect(query?.first { $0.name == "output_format" }?.value == "pcm_44100")
                #expect(query?.first { $0.name == "enable_logging" }?.value == "false")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "request")
                #expect(request.value(forHTTPHeaderField: "xi-api-key") == "request-key")
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("client ai-sdk-elevenlabs/") == true)
                let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
                #expect(body == .object([
                    "text": .string("Hello"), "model_id": .string("eleven_v3"), "language_code": .string("en"),
                    "voice_settings": .object(["speed": .number(1.25), "stability": .number(0.5), "similarity_boost": .number(0.8), "style": .number(0), "use_speaker_boost": .bool(false)]),
                    "seed": .number(0.5), "previous_text": .string("Before"), "next_text": .string("After"),
                    "pronunciation_dictionary_locators": .array([.object(["pronunciation_dictionary_id": .string("dictionary")])]),
                    "previous_request_ids": .array([]), "next_request_ids": .array([.string("next")]),
                    "apply_text_normalization": .string("off"), "apply_language_text_normalization": .bool(false)
                ]))
                return response(request, data: bytes, headers: ["x-request-id": "speech-1"])
            }
        ))
        let model = try #require(try provider.speechModel(modelId: "eleven_v3"))
        let result = try await model.doGenerate(options: .init(
            text: "Hello", voice: "voice", outputFormat: "pcm", instructions: "whisper", speed: 1.25,
            language: "en", providerOptions: ["elevenlabs": [
                "languageCode": .string("fr"),
                "voiceSettings": .object(["stability": .number(0.5), "similarityBoost": .number(0.8), "style": .number(0), "useSpeakerBoost": .bool(false)]),
                "seed": .number(0.5), "previousText": .string("Before"), "nextText": .string("After"),
                "pronunciationDictionaryLocators": .array([.object(["pronunciationDictionaryId": .string("dictionary"), "versionId": .string("")])]),
                "previousRequestIds": .array([]), "nextRequestIds": .array([.string("next")]),
                "applyTextNormalization": .string("off"), "applyLanguageTextNormalization": .bool(false), "enableLogging": .bool(false)
            ]], headers: ["authorization": "request", "xi-api-key": "request-key"]
        ))
        #expect(result.audio == .binary(bytes))
        #expect(result.response.modelId == "eleven_v3")
        #expect(result.response.headers?["x-request-id"] == "speech-1")
        #expect(result.warnings.count == 1)
        if case .unsupported(let feature, _) = result.warnings.first { #expect(feature == "instructions") }
        else { Issue.record("Expected unsupported instructions warning") }
        let requestBody = try #require(result.request?.body as? String)
        let echoed = try JSONDecoder().decode(JSONValue.self, from: Data(requestBody.utf8))
        if case .object(let body) = echoed { #expect(body["seed"] == .number(0.5)) }
        else { Issue.record("Expected JSON request metadata") }
    }

    @Test("speech defaults voice and output format")
    func speechDefaults() async throws {
        let model = createElevenLabs(settings: .init(apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/v1/text-to-speech/21m00Tcm4TlvDq8ikWAM")
            #expect(request.url?.query == "output_format=mp3_44100_128")
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object(["text": .string("Default"), "model_id": .string("custom-model")]))
            return response(request, data: Data([9]))
        })).speech(modelId: "custom-model")
        let result = try await model.doGenerate(options: .init(text: "Default"))
        #expect(result.audio == .binary(Data([9])))
    }

    @Test("speech rejects invalid provider options", arguments: [
        ["seed": .null],
        ["voiceSettings": .object(["stability": .number(1.1)])],
        ["previousRequestIds": .array([.string("1"), .string("2"), .string("3"), .string("4")])]
    ] as [JSONObject])
    func invalidSpeechOptions(_ values: JSONObject) async throws {
        let model = createElevenLabs().speech(modelId: .elevenV3)
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doGenerate(options: .init(text: "Invalid", providerOptions: ["elevenlabs": values]))
        }
    }

    @Test("API errors retain fractional and large numeric codes", arguments: [429.5, 1e100])
    func apiErrors(_ code: Double) async throws {
        let payload: JSONValue = .object(["error": .object(["message": .string("quota exhausted"), "code": .number(code)])])
        let data = try JSONEncoder().encode(payload)
        let model = createElevenLabs(settings: .init(apiKey: "key", fetch: { request in
            response(request, data: data, status: 429, headers: ["x-request-id": "error-1"])
        })).speech(modelId: .elevenV3)
        do {
            _ = try await model.doGenerate(options: .init(text: "Hello"))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.message == "quota exhausted")
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
            #expect(error.responseHeaders?["x-request-id"] == "error-1")
            #expect(error.responseBody == String(decoding: data, as: UTF8.self))
            #expect((error.data as? ElevenLabsErrorPayload)?.error.code == code)
        }
    }

    @Test("batch multipart and word metadata follow the provider schema")
    func transcriptionRequestAndMetadata() async throws {
        let words: [JSONValue] = [
            .object(["text": .string("Hi"), "type": .string("word"), "start": .null, "end": .number(0.4), "speaker_id": .string("speaker_1"), "characters": .array([
                .object(["text": .string("H"), "start": .null, "end": .number(0.2), "extra": .bool(true)])
            ]), "extra": .bool(true)]),
            .object(["text": .string(" "), "type": .string("spacing"), "end": .null]),
            .object(["text": .string("(noise)"), "type": .string("audio_event"), "start": .number(0.5), "end": .number(1e100), "speaker_id": .null, "characters": .null])
        ]
        let payload: JSONValue = .object(["language_code": .string("eng"), "language_probability": .number(0.99), "text": .string("Hi (noise)"), "words": .array(words), "raw": .number(1e100)])
        let data = try JSONEncoder().encode(payload)
        let timestamp = Date(timeIntervalSince1970: 42)
        let model = ElevenLabsTranscriptionModel(modelId: .scribeV2, config: .init(
            provider: "elevenlabs.transcription", url: { "https://api.elevenlabs.io\($0.path)" },
            fetch: { request in
                #expect(request.url?.path == "/v1/speech-to-text")
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
                for field in ["model_id\"\r\n\r\nscribe_v2", "diarize\"\r\n\r\nfalse", "language_code\"\r\n\r\nen", "num_speakers\"\r\n\r\n2", "timestamps_granularity\"\r\n\r\ncharacter", "tag_audio_events\"\r\n\r\nfalse", "file_format\"\r\n\r\npcm_s16le_16"] {
                    #expect(body.contains(field))
                }
                #expect(body.components(separatedBy: "name=\"diarize\"").count == 2)
                #expect(body.contains("filename=\"audio.wav\""))
                #expect(body.contains("Content-Type: audio/wav\r\n\r\nabc"))
                return response(request, data: data, headers: ["x-request-id": "batch-1"])
            }, currentDate: { timestamp }
        ))
        let result = try await model.doGenerate(options: .init(
            audio: .base64(Data("abc".utf8).base64EncodedString()), mediaType: "audio/wav",
            providerOptions: ["elevenlabs": ["languageCode": .string("en"), "numSpeakers": .number(2), "timestampsGranularity": .string("character"), "tagAudioEvents": .bool(false), "diarize": .bool(false), "fileFormat": .string("pcm_s16le_16"), "streaming": .object([:])]]
        ))
        #expect(result.text == "Hi (noise)")
        #expect(result.segments == [.init(text: "Hi", startSecond: 0, endSecond: 0.4), .init(text: " ", startSecond: 0, endSecond: 0), .init(text: "(noise)", startSecond: 0.5, endSecond: 1e100)])
        #expect(result.language == "eng")
        #expect(result.durationInSeconds == 1e100)
        #expect(result.response.timestamp == timestamp)
        #expect(result.response.headers?["x-request-id"] == "batch-1")
        #expect(try jsonValue(from: #require(result.response.body)) == payload)
        var expected = words
        expected[0] = .object(["text": .string("Hi"), "type": .string("word"), "start": .null, "end": .number(0.4), "speaker_id": .string("speaker_1"), "characters": .array([.object(["text": .string("H"), "start": .null, "end": .number(0.2)])])])
        #expect(result.providerMetadata == ["elevenlabs": ["words": .array(expected)]])
        #expect(result.warnings.count == 1)
    }

    @Test("batch default options distinguish omitted options from null fields", arguments: [0, 1, 2])
    func transcriptionDefaults(_ variant: Int) async throws {
        let model = createElevenLabs(settings: .init(apiKey: "key", fetch: { request in
            let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
            #expect(body.contains("name=\"diarize\"\r\n\r\ntrue"))
            #expect(body.contains("name=\"tag_audio_events\"") == (variant == 1))
            #expect(body.contains("name=\"timestamps_granularity\"") == (variant == 1))
            #expect(body.contains("name=\"file_format\"") == (variant == 1))
            return response(request, data: Data(#"{"language_code":"en","language_probability":1,"text":"Empty","words":null}"#.utf8))
        }))(.scribeV1).transcription
        let providerOptions: SharedV4ProviderOptions? = variant == 0 ? nil : ["elevenlabs": variant == 1 ? [:] : ["tagAudioEvents": .null, "timestampsGranularity": .null, "diarize": .null, "fileFormat": .null]]
        let result = try await model.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: providerOptions))
        #expect(result.text == "Empty")
        #expect(result.segments.isEmpty)
        #expect(result.providerMetadata == nil)
    }

    @Test("batch rejects words outside the upstream response enum")
    func invalidTranscriptionResponse() async throws {
        let model = createElevenLabs(settings: .init(apiKey: "key", fetch: { request in
            response(request, data: Data(#"{"language_code":"en","language_probability":1,"text":"Hi","words":[{"text":"Hi","type":"unknown"}]}"#.utf8))
        })).transcription(modelId: .scribeV2)
        do {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
            Issue.record("Expected invalid response failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            let values = try #require(error.requestBodyValues as? [String: Any])
            #expect(values["model_id"] as? String == "scribe_v2")
            #expect(values["diarize"] as? String == "true")
            #expect(values["file"] as? Data == Data([1]))
        }
    }

    @Test("batch rejects a realtime-only model")
    func unsupportedBatchModel() async throws {
        let model = createElevenLabs().transcription(modelId: .scribeV2Realtime)
        await #expect(throws: UnsupportedFunctionalityError.self) {
            try await model.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        }
    }

    @Suite("lazy credentials", .serialized)
    struct Credentials {
        @Test("missing credentials fail from the operation")
        func missingKey() async throws {
            let original = getenv("ELEVENLABS_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original { setenv("ELEVENLABS_API_KEY", original, 1) }
                else { unsetenv("ELEVENLABS_API_KEY") }
            }
            unsetenv("ELEVENLABS_API_KEY")
            let provider: any ProviderV4 = createElevenLabs()
            let speech = try #require(try provider.speechModel(modelId: "eleven_v3"))
            let transcription = try #require(try provider.transcriptionModel(modelId: "scribe_v2"))
            await #expect(throws: LoadAPIKeyError.self) {
                try await speech.doGenerate(options: .init(text: "Hello"))
            }
            await #expect(throws: LoadAPIKeyError.self) {
                try await transcription.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
            }
        }
    }
}

private func response(_ request: URLRequest, data: Data, status: Int = 200, headers: [String: String] = [:]) -> FetchResponse {
    FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
}

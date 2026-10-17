import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import MistralProvider

@Suite("MistralTranscriptionModel")
struct MistralTranscriptionModelTests {
    private func model(
        response: String = #"{"model":"voxtral-response-model","text":"Hello"}"#,
        status: Int = 200,
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> MistralTranscriptionModel {
        MistralTranscriptionModel(
            modelId: .voxtralMiniLatest,
            config: .init(
                provider: "mistral.transcription",
                baseURL: "https://api.mistral.ai/v1",
                fetch: { request in
                    try inspect(request)
                    return FetchResponse(
                        body: .data(Data(response.utf8)),
                        urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Request-Id": "transcription-id"])!
                    )
                },
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    private func fieldValues(_ name: String, request: URLRequest) throws -> [String] {
        let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
        let pattern = "name=\"\(NSRegularExpression.escapedPattern(for: name))\"\r\n\r\n(.*?)\r\n"
        let regex = try NSRegularExpression(pattern: pattern, options: .dotMatchesLineSeparators)
        let string = body as NSString
        return regex.matches(in: body, range: NSRange(location: 0, length: string.length)).map { string.substring(with: $0.range(at: 1)) }
    }

    @Test("binary and base64 audio preserve bytes and media-derived multipart filenames", arguments: [false, true])
    func audioUpload(base64: Bool) async throws {
        let audio = Data([0, 1, 2, 3, 255])
        let mediaType = base64 ? "audio/mp4" : "audio/wav"
        let filename = base64 ? "audio.m4a" : "audio.wav"
        let result = try await model { request in
            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/audio/transcriptions")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
            let modelValues = try fieldValues("model", request: request)
            #expect(modelValues == ["voxtral-mini-latest"])
            var file = Data("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(mediaType)\r\n\r\n".utf8)
            file.append(audio)
            file.append(Data("\r\n".utf8))
            let body = try #require(request.httpBody)
            #expect(body.range(of: file) != nil)
        }.doGenerate(options: .init(audio: base64 ? .base64(audio.base64EncodedString()) : .binary(audio), mediaType: mediaType))
        #expect(result.text == "Hello")
        #expect(result.segments.isEmpty)
        #expect(result.durationInSeconds == nil)
        #expect(result.providerMetadata == nil)
    }

    @Test("Mistral transcription options become repeated multipart fields")
    func providerOptions() async throws {
        let result = try await model { request in
            let temperature = try fieldValues("temperature", request: request)
            let granularities = try fieldValues("timestamp_granularities", request: request)
            let diarize = try fieldValues("diarize", request: request)
            let contextBias = try fieldValues("context_bias", request: request)
            #expect(temperature == ["0.2"])
            #expect(granularities == ["segment", "word"])
            #expect(diarize == ["false"])
            #expect(contextBias == ["Vercel", "AI_SDK"])
        }.doGenerate(options: .init(
            audio: .binary(Data([1])), mediaType: "audio/wav",
            providerOptions: ["mistral": [
                "temperature": .number(0.2), "timestampGranularities": .array([.string("segment"), .string("word")]),
                "diarize": .bool(false), "contextBias": .array([.string("Vercel"), .string("AI_SDK")])
            ]]
        ))
        #expect(result.warnings.isEmpty)
    }

    @Test("language and zero temperature are encoded as multipart text")
    func language() async throws {
        _ = try await model { request in
            let language = try fieldValues("language", request: request)
            let temperature = try fieldValues("temperature", request: request)
            #expect(language == ["en"])
            #expect(temperature == ["0"])
        }.doGenerate(options: .init(audio: .base64("AQ=="), mediaType: "audio/wav", providerOptions: ["mistral": ["language": .string("en"), "temperature": .number(-0.0)]]))
    }

    @Test("invalid options are rejected before HTTP", arguments: [
        ["language": JSONValue.string("")],
        ["language": .null],
        ["temperature": .string("0.2")],
        ["timestampGranularities": .array([])],
        ["timestampGranularities": .array([.string("sentence")])],
        ["diarize": .null],
        ["contextBias": .array([.string("")])],
        ["contextBias": .array([.string("AI SDK")])],
        ["contextBias": .array([.string("AI,SDK")])],
        ["contextBias": .array([.string("AI\u{FEFF}SDK")])],
        ["contextBias": .array(Array(repeating: .string("bias"), count: 101))]
    ])
    func invalidOptions(options: JSONObject) async throws {
        let instance = model { _ in Issue.record("Invalid transcription options must not reach HTTP") }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await instance.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["mistral": options]))
        }
    }

    @Test("language conflicts with timestamp granularities before HTTP")
    func conflictingOptions() async throws {
        let instance = model { _ in Issue.record("Conflicting options must not reach HTTP") }
        do {
            _ = try await instance.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", providerOptions: ["mistral": ["language": .string("en"), "timestampGranularities": .array([.string("segment")])]]))
            Issue.record("Expected invalid argument")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "providerOptions.mistral.language cannot be combined with providerOptions.mistral.timestampGranularities")
        }
    }

    @Test("transcripts expose usage, selective diarization metadata, duration, and the response model")
    func responseMetadata() async throws {
        let payload = #"{"model":"voxtral-response-model","text":"Hello world!","language":"en","segments":[{"type":"transcription_segment","text":"Hello","start":0,"end":1,"speaker_id":"speaker_1"},{"text":" world","start":1,"end":2,"score":0},{"text":"!","start":2,"end":3}],"usage":{"prompt_tokens":13,"completion_tokens":151,"total_tokens":164,"prompt_audio_seconds":36,"request_count":1,"unknown":5},"extra":"raw"}"#
        let result = try await model(response: payload).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.text == "Hello world!")
        #expect(result.language == "en")
        #expect(result.segments == [
            .init(text: "Hello", startSecond: 0, endSecond: 1),
            .init(text: " world", startSecond: 1, endSecond: 2),
            .init(text: "!", startSecond: 2, endSecond: 3)
        ])
        #expect(result.durationInSeconds == 36)
        #expect(result.usage == ["prompt_tokens": .number(13), "completion_tokens": .number(151), "total_tokens": .number(164), "prompt_audio_seconds": .number(36), "request_count": .number(1)])
        #expect(result.providerMetadata == ["mistral": [
            "usage": .object(["promptTokens": .number(13), "completionTokens": .number(151), "totalTokens": .number(164), "promptAudioSeconds": .number(36), "requestCount": .number(1)]),
            "segments": .array([
                .object(["type": .string("transcription_segment"), "text": .string("Hello"), "startSecond": .number(0), "endSecond": .number(1), "speakerId": .string("speaker_1")]),
                .object(["text": .string(" world"), "startSecond": .number(1), "endSecond": .number(2), "score": .number(0)])
            ])
        ]])
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "voxtral-response-model")
        #expect(result.response.headers?["x-request-id"] == "transcription-id")
        let rawResponse = try jsonValue(from: #require(result.response.body))
        let expectedResponse = try JSONDecoder().decode(JSONValue.self, from: Data(payload.utf8))
        #expect(rawResponse == expectedResponse)
    }

    @Test("nullable segment metadata falls back to the last segment duration")
    func nullableResponse() async throws {
        let result = try await model(response: #"{"model":"voxtral-response-model","text":"Hello","language":null,"segments":[{"text":"Hello","start":0,"end":2.5,"type":null,"score":null,"speaker_id":null}],"usage":null}"#).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.language == nil)
        #expect(result.durationInSeconds == 2.5)
        #expect(result.usage == nil)
        #expect(result.providerMetadata == nil)
    }

    @Test("native usage preserves nulls while metadata omits them and zero duration wins")
    func nullableUsage() async throws {
        let result = try await model(response: #"{"model":"voxtral-response-model","text":"Hello","language":"","segments":[{"text":"Hello","start":0,"end":2.5}],"usage":{"prompt_tokens":null,"prompt_audio_seconds":0}}"#).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
        #expect(result.durationInSeconds == 0)
        #expect(result.language == "")
        #expect(result.usage == ["prompt_tokens": .null, "prompt_audio_seconds": .number(0)])
        #expect(result.providerMetadata == ["mistral": ["usage": .object(["promptAudioSeconds": .number(0)])]])
    }

    @Test("invalid transcription response data rejects", arguments: [
        #"{"text":"Hello"}"#,
        #"{"model":"model","text":"Hello","segments":[{"text":"Hello","start":0,"end":1,"type":"wrong"}]}"#,
        #"{"model":"model","text":"Hello","usage":{"prompt_audio_seconds":"1"}}"#
    ])
    func invalidResponse(payload: String) async throws {
        do {
            _ = try await model(response: payload).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav"))
            Issue.record("Expected response validation failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.message == "Invalid JSON response")
        }
    }

    @Test("transcription API errors preserve the provider message")
    func apiError() async throws {
        do {
            _ = try await model(response: #"{"object":"error","message":"Unsupported audio","type":"invalid_request_error","param":"file","code":"invalid_audio"}"#, status: 422).doGenerate(options: .init(
                audio: .binary(Data([1])), mediaType: "audio/wav",
                providerOptions: ["mistral": ["timestampGranularities": .array([.string("segment"), .string("word")])]]
            ))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.statusCode == 422)
            #expect(error.message == "Unsupported audio")
            let values = try #require(error.requestBodyValues as? [String: Any])
            #expect(values["model"] as? String == "voxtral-mini-latest")
            #expect(values["file"] as? Data == Data([1]))
            #expect(values["timestamp_granularities"] as? String == "word")
        }
    }

    @Test("aborted transcription does not send audio to the API")
    func cancellation() async throws {
        let instance = model { _ in Issue.record("Aborted transcription must not reach HTTP") }
        await #expect(throws: CancellationError.self) {
            _ = try await instance.doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", abortSignal: { true }))
        }
    }

    @Test("provider transcription uses custom endpoints, authentication, headers, and the Mistral user agent")
    func providerHeaders() async throws {
        let provider = createMistral(settings: .init(
            baseURL: "https://custom.mistral.example/v2/",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-value"],
            fetch: { request in
                #expect(request.url?.absoluteString == "https://custom.mistral.example/v2/audio/transcriptions")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
                #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-value")
                #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-value")
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-mistral/\(MISTRAL_VERSION)") == true)
                #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
                return FetchResponse(body: .data(Data(#"{"model":"voxtral-mini-2602","text":"Hello"}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
        ))
        let result = try await provider.transcription(.voxtralMini2602).doGenerate(options: .init(audio: .binary(Data([1])), mediaType: "audio/wav", headers: ["Custom-Request-Header": "request-value"]))
        #expect(result.text == "Hello")
    }
}

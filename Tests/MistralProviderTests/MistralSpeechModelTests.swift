import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import MistralProvider

@Suite("MistralSpeechModel")
struct MistralSpeechModelTests {
    private func model(
        response: String = #"{"audio_data":"YXVkaW8=","extra":"preserved"}"#,
        status: Int = 200,
        inspect: @escaping @Sendable (URLRequest) throws -> Void = { _ in }
    ) -> MistralSpeechModel {
        MistralSpeechModel(
            modelId: .voxtralMiniTts2603,
            config: .init(
                provider: "mistral.speech",
                baseURL: "https://api.mistral.ai/v1",
                fetch: { request in
                    try inspect(request)
                    return FetchResponse(
                        body: .data(Data(response.utf8)),
                        urlResponse: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type": "application/json", "X-Request-Id": "speech-id"])!
                    )
                },
                currentDate: { Date(timeIntervalSince1970: 0) }
            )
        )
    }

    @Test("non-streaming synthesis maps input, voice, and base64 response metadata")
    func synthesis() async throws {
        let result = try await model { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.absoluteString == "https://api.mistral.ai/v1/audio/speech")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object([
                "model": .string("voxtral-mini-tts-2603"), "input": .string("Hello"),
                "voice_id": .string("voice-id"), "response_format": .string("mp3"), "stream": .bool(false)
            ]))
        }.doGenerate(options: .init(text: "Hello", voice: "voice-id"))

        #expect(result.audio == .base64("YXVkaW8="))
        #expect(result.warnings.isEmpty)
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "voxtral-mini-tts-2603")
        #expect(result.response.headers?["x-request-id"] == "speech-id")
        let raw = try jsonValue(from: #require(result.response.body))
        #expect(raw == .object(["audio_data": .string("YXVkaW8="), "extra": .string("preserved")]))
    }

    @Test("supported codecs are sent without warnings", arguments: ["pcm", "wav", "mp3", "flac", "opus"])
    func formats(format: String) async throws {
        let result = try await model { request in
            let body = try decodeJSONBody(request)
            #expect(body["response_format"] as? String == format)
        }.doGenerate(options: .init(text: "Hello", outputFormat: format))
        #expect(result.warnings.isEmpty)
    }

    @Test("unsupported speech options warn in order and fall back to MP3")
    func unsupportedOptions() async throws {
        let result = try await model { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object([
                "model": .string("voxtral-mini-tts-2603"), "input": .string("Hello"),
                "response_format": .string("mp3"), "stream": .bool(false)
            ]))
        }.doGenerate(options: .init(text: "Hello", outputFormat: "aac", instructions: "cheerful", speed: 1.2, language: "en"))
        #expect(result.warnings == [
            .unsupported(feature: "outputFormat", details: "Unsupported output format: aac. Using mp3 instead."),
            .unsupported(feature: "instructions", details: "Mistral speech models do not support the `instructions` option. Use a reference audio clip to guide delivery."),
            .unsupported(feature: "speed", details: "Mistral speech models do not support the `speed` option. It was ignored."),
            .unsupported(feature: "language", details: "Mistral speech models do not support the `language` option. Language is inferred from the input text and voice.")
        ])
    }

    @Test("reference audio overrides voice and is redacted in request metadata")
    func referenceAudio() async throws {
        let result = try await model { request in
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object([
                "model": .string("voxtral-mini-tts-2603"), "input": .string("Hello"),
                "ref_audio": .string("sensitive-reference-audio"), "response_format": .string("mp3"), "stream": .bool(false)
            ]))
        }.doGenerate(options: .init(text: "Hello", voice: "ignored", providerOptions: ["mistral": ["refAudio": .string("sensitive-reference-audio")]]))
        let requestBody = try #require(result.request?.body as? String)
        let metadata = try JSONDecoder().decode(JSONValue.self, from: Data(requestBody.utf8))
        #expect(metadata == .object([
            "model": .string("voxtral-mini-tts-2603"), "input": .string("Hello"),
            "ref_audio": .string("[redacted]"), "response_format": .string("mp3"), "stream": .bool(false)
        ]))
    }

    @Test("API failures keep the provider message and redact reference audio")
    func apiError() async throws {
        let instance = model(response: #"{"object":"error","message":"Rejected reference audio","type":"invalid_request_error","param":"ref_audio","code":"invalid_reference_audio"}"#, status: 400)
        do {
            _ = try await instance.doGenerate(options: .init(text: "Hello", providerOptions: ["mistral": ["refAudio": .string("secret")]]))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == "Rejected reference audio")
            #expect(error.statusCode == 400)
            let body = try jsonValue(from: #require(error.requestBodyValues))
            #expect(body == .object([
                "model": .string("voxtral-mini-tts-2603"), "input": .string("Hello"),
                "ref_audio": .string("[redacted]"), "response_format": .string("mp3"), "stream": .bool(false)
            ]))
        }
    }

    @Test("invalid reference audio rejects before HTTP", arguments: [JSONValue.string(""), .null, .number(1)])
    func invalidReferenceAudio(value: JSONValue) async throws {
        let instance = model { _ in Issue.record("Invalid provider options must not reach HTTP") }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await instance.doGenerate(options: .init(text: "Hello", providerOptions: ["mistral": ["refAudio": value]]))
        }
    }

    @Test("invalid response envelopes are typed API failures")
    func invalidResponse() async throws {
        do {
            _ = try await model(response: #"{"audio_data":123}"#).doGenerate(options: .init(text: "Hello"))
            Issue.record("Expected response validation failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 200)
            #expect(error.message == "Invalid JSON response")
        }
    }

    @Test("aborted synthesis does not send audio to the API")
    func cancellation() async throws {
        let instance = model { _ in Issue.record("Aborted synthesis must not reach HTTP") }
        await #expect(throws: CancellationError.self) {
            _ = try await instance.doGenerate(options: .init(text: "Hello", abortSignal: { true }))
        }
    }

    @Test("provider synthesis uses custom endpoints, authentication, merged headers, and the Mistral user agent")
    func providerHeaders() async throws {
        let provider = createMistral(settings: .init(
            baseURL: "https://custom.mistral.example/v2/",
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-value", "Override": "provider"],
            fetch: { request in
                #expect(request.url?.absoluteString == "https://custom.mistral.example/v2/audio/speech")
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-api-key")
                #expect(request.value(forHTTPHeaderField: "Custom-Provider-Header") == "provider-value")
                #expect(request.value(forHTTPHeaderField: "Custom-Request-Header") == "request-value")
                #expect(request.value(forHTTPHeaderField: "Override") == "request")
                #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-mistral/\(MISTRAL_VERSION)") == true)
                return FetchResponse(body: .data(Data(#"{"audio_data":"YXVkaW8="}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
            }
        ))
        let result = try await provider.speech(.voxtralMiniTtsLatest).doGenerate(options: .init(text: "Hello", headers: ["Custom-Request-Header": "request-value", "Override": "request"]))
        #expect(result.audio == .base64("YXVkaW8="))
    }
}

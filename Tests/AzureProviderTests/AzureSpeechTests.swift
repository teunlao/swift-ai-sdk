import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AzureProvider

private final class AzureSpeechFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = false
    var value: Bool { lock.withLock { flag } }
    func set() { lock.withLock { flag = true } }
}

private actor SpeechRequests {
    private var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
    func all() -> [URLRequest] { requests }
}

private func speechResponse(_ request: URLRequest, body: ProviderHTTPResponseBody = .data(Data([0xff, 0xf3, 0x44, 0xc4])), status: Int = 200) -> FetchResponse {
    FetchResponse(body: body, urlResponse: HTTPURLResponse(url: request.url!, statusCode: status,
        httpVersion: nil, headerFields: ["Content-Type": "audio/mpeg", "X-Request-Id": "speech-request"])!)
}

private func speechSSML(_ voice: String, _ content: String, locale: String = "en-US") -> String {
    "<speak version=\"1.0\" xmlns=\"http://www.w3.org/2001/10/synthesis\" xmlns:mstts=\"http://www.w3.org/2001/mstts\" xml:lang=\"\(locale)\"><voice name=\"\(voice)\">\(content)</voice></speak>"
}

@Suite("Azure Speech generation")
struct AzureSpeechTests {
    @Test("MAI voices generate SSML with Speech headers and binary audio")
    func generation() async throws {
        let requests = SpeechRequests()
        let provider = try createAzure(settings: .init(resourceName: "speech-resource", apiKey: "speech-key",
            headers: ["Content-Type": "provider/type", "X-Microsoft-OutputFormat": "provider-format", "X-Provider": "configured"],
            fetch: { request in
                await requests.append(request)
                let stream = AsyncThrowingStream<Data, Error> { continuation in
                    continuation.yield(Data([0xff, 0xf3]))
                    continuation.yield(Data([0x44, 0xc4]))
                    continuation.finish()
                }
                return speechResponse(request, body: .stream(stream))
            }))
        let before = Date()
        let model: any SpeechModelV4 = try #require(try provider.speechModel(modelId: "mAi-VoIcE-2.1-fLaSh"))
        let result = try await model.doGenerate(options: .init(
            text: "Том & <Джерри> \"цитата\" 'текст'", voice: "de-DE-Mia\"><evil", outputFormat: "WAV", speed: 1.25,
            providerOptions: ["azure": ["style": "a\"b", "styleDegree": 1.5]], headers: ["X-Provider": "caller"]))
        let request = try #require(await requests.all().first)
        let ssml = speechSSML("de-DE-Mia&quot;&gt;&lt;evil:MAI-Voice-2.1-Flash",
            "<mstts:express-as style=\"a&quot;b\" styledegree=\"1.5\"><prosody rate=\"1.25\">Том &amp; &lt;Джерри&gt; &quot;цитата&quot; &apos;текст&apos;</prosody></mstts:express-as>", locale: "de-DE")
        #expect(request.url?.absoluteString == "https://speech-resource.cognitiveservices.azure.com/tts/cognitiveservices/v1")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/ssml+xml")
        #expect(request.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "riff-24khz-16bit-mono-pcm")
        #expect(request.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == "speech-key")
        #expect(request.value(forHTTPHeaderField: "api-key") == nil)
        #expect(request.value(forHTTPHeaderField: "X-Provider") == "caller")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-azure/") == true)
        #expect(String(decoding: try #require(request.httpBody), as: UTF8.self) == ssml)
        #expect(result.request?.body as? String == ssml)
        #expect(result.audio == .binary(Data([0xff, 0xf3, 0x44, 0xc4])))
        #expect(result.warnings == [])
        #expect(result.response.modelId == "mAi-VoIcE-2.1-fLaSh")
        #expect(result.response.headers?["x-request-id"] == "speech-request")
        #expect(result.response.timestamp >= before && result.response.timestamp <= Date())
    }

    @Test("Known MAI voice IDs select Speech and canonical model suffixes", arguments: [
        ("mai-voice-2", "MAI-Voice-2"), ("MaI-VoIcE-2-fLaSh", "MAI-Voice-2-Flash"),
        ("MAI-Voice-2.1", "MAI-Voice-2.1"), ("mai-voice-2.1-flash", "MAI-Voice-2.1-Flash"),
        ("mai-voice-2-custom", nil)
    ] as [(String, String?)])
    func routing(_ id: String, _ suffix: String?) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key",
            fetch: { request in speechResponse(request) }))
        let model = provider.speech(id)
        let result = try await model.doGenerate(options: .init(text: "Hi"))
        let body = try #require(result.request?.body as? String)
        if let suffix { #expect(body == speechSSML("en-US-Harper:\(suffix)", "Hi")) }
        else {
            let json = try JSONDecoder().decode(JSONObject.self, from: Data(body.utf8))
            #expect(json["model"] == .string(id))
            #expect(json["voice"] == "alloy")
        }
        #expect(result.audio == .binary(Data([0xff, 0xf3, 0x44, 0xc4])))
    }

    @Test("Each call resolves its API and retains native header precedence")
    func selection() async throws {
        let requests = SpeechRequests()
        let provider = try createAzure(settings: .init(baseURL: "https://proxy.example.com/openai/",
            speechBaseURL: "https://eastus.api.cognitive.microsoft.com/", tokenProvider: { "entra-speech" },
            headers: ["X-Provider": "configured"], fetch: { request in
                await requests.append(request)
                return speechResponse(request)
            }, apiVersion: "ignored-for-speech", useDeploymentBasedUrls: true))
        let model = provider.speechModel("MAI-Voice-2")
        let first = try await model.doGenerate(options: .init(text: "Hi", headers: [
            "content-type": "caller/ssml", "x-microsoft-outputformat": "caller-format", "X-Provider": "caller"]))
        let options = AzureSpeechModelOptions(api: .openai, style: " ", styleDegree: 0.01)
        let fields = try JSONDecoder().decode(JSONObject.self, from: JSONEncoder().encode(options))
        let second = try await model.doGenerate(options: .init(text: "Hi", speed: 1.5,
            providerOptions: ["azure": fields, "openai": ["speed": 2, "instructions": ""]],
            headers: ["Authorization": "Bearer caller"]))
        let all = await requests.all()
        #expect(all.map { $0.url?.absoluteString } == [
            "https://eastus.api.cognitive.microsoft.com/tts/cognitiveservices/v1",
            "https://proxy.example.com/openai/deployments/MAI-Voice-2/audio/speech?api-version=ignored-for-speech"])
        #expect(all[0].value(forHTTPHeaderField: "Content-Type") == "caller/ssml")
        #expect(all[0].value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == "caller-format")
        #expect(all[0].value(forHTTPHeaderField: "X-Provider") == "caller")
        #expect(all.map { $0.value(forHTTPHeaderField: "Authorization") } == ["Bearer entra-speech", "Bearer caller"])
        #expect(all.allSatisfy { $0.value(forHTTPHeaderField: "Ocp-Apim-Subscription-Key") == nil && $0.value(forHTTPHeaderField: "api-key") == nil })
        #expect(first.request?.body as? String == speechSSML("en-US-Harper:MAI-Voice-2", "Hi"))
        let body = try JSONDecoder().decode(JSONObject.self, from: #require(all[1].httpBody))
        #expect(body == ["model": "MAI-Voice-2", "input": "Hi", "voice": "alloy", "response_format": "mp3", "speed": 2, "instructions": ""])
        #expect(second.warnings == [
            .unsupported(feature: "providerOptions.azure.style", details: "This option requires the Azure Speech API."),
            .unsupported(feature: "providerOptions.azure.styleDegree", details: "This option requires the Azure Speech API.")
        ])
    }

    @Test("Output formats use shorthand or the exact lowercase ASCII grammar", arguments: [
        ("mp3", "audio-24khz-160kbitrate-mono-mp3"), ("OPUS", "ogg-24khz-16bit-mono-opus"),
        ("pcm", "raw-24khz-16bit-mono-pcm"), ("audio-48khz-192kbitrate-mono-mp3", "audio-48khz-192kbitrate-mono-mp3"),
        ("amr--", "amr--"), ("audio-x\n", nil), ("audio-ā", nil), ("", nil)
    ] as [(String, String?)])
    func formats(_ format: String, _ expected: String?) async throws {
        let provider = try createAzure(settings: .init(speechBaseURL: "https://speech.example.com", apiKey: "key", fetch: { request in
            #expect(request.value(forHTTPHeaderField: "X-Microsoft-OutputFormat") == (expected ?? "audio-24khz-160kbitrate-mono-mp3"))
            return speechResponse(request)
        }))
        let result = try await provider.speech("MAI-Voice-2").doGenerate(options: .init(text: "Hi", outputFormat: format))
        #expect(result.warnings == (expected == nil ? [.unsupported(feature: "outputFormat", details: "Unsupported output format: \(format). Using mp3 instead.")] : []))
        #expect(result.audio == .binary(Data([0xff, 0xf3, 0x44, 0xc4])))
    }

    @Test("Language defaults and explicit voice locales preserve SOURCE precedence", arguments: [
        (nil, "FR-ca", "fr-FR-Soleil:MAI-Voice-2", "fr-FR", nil),
        (nil, "ko-KR", "ko-KR-Haena:MAI-Voice-2", "ko-KR", nil),
        ("es-MX-Valeria:MAI-Voice-2-Flash", "auto", "es-MX-Valeria:MAI-Voice-2-Flash", "es-MX", nil),
        ("eng-Latn-Voice", "ENG", "eng-Latn-Voice:MAI-Voice-2", "eng-Latn", nil),
        ("Ko-KR-X", "de", "Ko-KR-X:MAI-Voice-2", "en-US", nil),
        ("en-US-Ethan", "de", "en-US-Ethan:MAI-Voice-2", "en-US", "The voice en-US-Ethan selects the language. Language \"de\" was ignored."),
        (nil, "auto", "en-US-Harper:MAI-Voice-2", "en-US", "Automatic language detection is not supported. en-US-Harper was used."),
        (nil, "ja", "en-US-Harper:MAI-Voice-2", "en-US", "No default MAI voice for language \"ja\". en-US-Harper was used.")
    ] as [(String?, String, String, String, String?)])
    func language(_ voice: String?, _ language: String, _ expectedVoice: String, _ locale: String, _ warning: String?) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { speechResponse($0) }))
        let result = try await provider.speech("MAI-Voice-2").doGenerate(options: .init(text: "Hi", voice: voice, language: language))
        #expect(result.request?.body as? String == speechSSML(expectedVoice, "Hi", locale: locale))
        #expect(result.warnings == warning.map { [.unsupported(feature: "language", details: $0)] } ?? [])
    }

    @Test("Empty values stay distinct from missing values and orphan degree is ignored")
    func emptyValues() async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { speechResponse($0) }))
        let result = try await provider.speech("MAI-Voice-2").doGenerate(options: .init(
            text: "", voice: "", outputFormat: "", instructions: "", speed: 0, language: "",
            providerOptions: ["azure": ["styleDegree": 2]]))
        #expect(result.request?.body as? String == speechSSML(":MAI-Voice-2", "<prosody rate=\"0\"></prosody>"))
        #expect(result.warnings == [
            .unsupported(feature: "instructions", details: "Use providerOptions.azure.style to control speaking style."),
            .unsupported(feature: "providerOptions.azure.styleDegree", details: "styleDegree requires style."),
            .unsupported(feature: "outputFormat", details: "Unsupported output format: . Using mp3 instead.")
        ])
    }

    @Test("Strict Azure speech options reject unknown fields, nulls and invalid ratios", arguments: [
        ["emotion": JSONValue.string("happy")], ["api": .string("mai")], ["api": .null],
        ["style": .string("")], ["style": .null], ["styleDegree": .number(0)],
        ["styleDegree": .number(2.5)], ["styleDegree": .bool(false)]
    ])
    func optionValidation(_ fields: JSONObject) async throws {
        let provider = try createAzure(settings: .init(fetch: { _ in throw URLError(.cannotConnectToHost) }))
        let error = await #expect(throws: InvalidArgumentError.self) {
            try await provider.speech("MAI-Voice-2").doGenerate(options: .init(text: "Hi", providerOptions: ["azure": fields]))
        }
        #expect(error?.argument == "providerOptions")
    }

    @Test("SSML speed uses SOURCE decimal and exponent spelling", arguments: [
        (1e-7, "1e-7"), (1e-6, "0.000001"), (1e20, "100000000000000000000"),
        (-0.0, "0"), (.nan, "NaN"), (.infinity, "Infinity"), (-.infinity, "-Infinity")
    ])
    func numericSpeed(_ speed: Double, _ spelling: String) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            let body = String(decoding: try #require(request.httpBody), as: UTF8.self)
            #expect(body == speechSSML("en-US-Harper:MAI-Voice-2", "<prosody rate=\"\(spelling)\">Hi</prosody>"))
            return speechResponse(request)
        }))
        let result = try await provider.speech("MAI-Voice-2").doGenerate(options: .init(text: "Hi", speed: speed))
        #expect(result.audio == .binary(Data([0xff, 0xf3, 0x44, 0xc4])))
    }

    @Test("Speech abort at binary handoff releases the retained audio source")
    func cancellation() async throws {
        let aborted = AzureSpeechFlag()
        let cancelled = AzureSpeechFlag()
        let timedOut = AzureSpeechFlag()
        let source = AsyncThrowingStream<Data, Error>.makeStream()
        source.continuation.onTermination = { reason in if case .cancelled = reason { cancelled.set() } }
        defer { source.continuation.finish() }
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: { request in
            aborted.set()
            return speechResponse(request, body: .stream(source.stream))
        }))
        let operation = Task {
            try await provider.speech("MAI-Voice-2").doGenerate(options: .init(text: "Hi", abortSignal: { aborted.value }))
        }
        let watchdog = Task {
            do { try await Task.sleep(for: .seconds(1)) } catch { return }
            timedOut.set()
            operation.cancel()
        }
        defer { watchdog.cancel(); operation.cancel() }
        _ = await #expect(throws: CancellationError.self) { try await operation.value }
        #expect(!timedOut.value)
        #expect(cancelled.value)
        withExtendedLifetime(source) {}
    }

    @Test("Speech errors preserve SSML diagnostics and classify voice resets", arguments: [
        (400, "", 400, false, "Azure Speech request failed with status 400. Check the voice name, style, and output format."),
        (401, "\u{feff}" + #"{"error":{"message":"Доступ запрещён","code":"401"}}"#, 401, false, "Доступ запрещён"),
        (502, "upstream reset reason: protocol error", 400, false, "Azure Speech could not synthesize the request. Check that the voice is available for this model and that the style is supported by the voice."),
        (502, "unavailable", 502, true, "Azure Speech request failed with status 502."),
        (502, #"{"error":{"message":"reset reason: protocol error"}}"#, 400, false, "reset reason: protocol error")
    ])
    func errors(_ status: Int, _ body: String, _ expectedStatus: Int, _ retryable: Bool, _ message: String) async throws {
        let provider = try createAzure(settings: .init(resourceName: "resource", apiKey: "key", fetch: {
            speechResponse($0, body: .data(Data(body.utf8)), status: status)
        }))
        let error = await #expect(throws: APICallError.self) {
            try await provider.speech("MAI-Voice-2").doGenerate(options: .init(text: "Hi"))
        }
        #expect(error?.statusCode == expectedStatus)
        #expect(error?.isRetryable == retryable)
        #expect(error?.message == message)
        #expect(error?.responseBody == (body.hasPrefix("\u{feff}") ? String(body.dropFirst()) : body))
        #expect(error?.requestBodyValues as? String == speechSSML("en-US-Harper:MAI-Voice-2", "Hi"))
        #expect(error?.responseHeaders?["x-request-id"] == "speech-request")
    }
}

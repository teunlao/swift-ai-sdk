import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

private let speechAudioData = Data([0x01, 0x02, 0x03])

@Suite("OpenAISpeechModel")
struct OpenAISpeechModelTests {
    @Test("doGenerate sends JSON request with options")
    func testDoGenerateSendsJSON() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = Capture()

        let mockFetch: FetchFunction = { request in
            await capture.store(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/opus"]
            )!
            return FetchResponse(body: .data(speechAudioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { ["Authorization": "Bearer test-key"] },
            fetch: mockFetch,
            _internal: .init(currentDate: { Date(timeIntervalSince1970: 0) })
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: "Hello from Swift",
                voice: "nova",
                outputFormat: "opus",
                speed: 1.25,
                providerOptions: [
                    "openai": [
                        "instructions": .string("Speak softly"),
                        "speed": .number(1.1)
                    ]
                ],
                headers: ["Custom-Header": "request-header-value"]
            )
        )

        #expect(result.audio == .binary(speechAudioData))
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 0))
        #expect(result.response.modelId == "tts-1")

        guard let request = await capture.value() else {
            Issue.record("No request captured")
            return
        }

        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.openai.com/v1/audio/speech")

        let headers = request.allHTTPHeaderFields ?? [:]
        let normalizedHeaders = Dictionary(uniqueKeysWithValues: headers.map { ($0.key.lowercased(), $0.value) })
        #expect(normalizedHeaders["authorization"] == "Bearer test-key")
        #expect(normalizedHeaders["custom-header"] == "request-header-value")
        #expect(normalizedHeaders["content-type"] == "application/json")

        guard let body = request.httpBody else {
            Issue.record("Missing request body")
            return
        }

        let jsonObject = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        #expect(jsonObject?["model"] as? String == "tts-1")
        #expect(jsonObject?["input"] as? String == "Hello from Swift")
        #expect(jsonObject?["voice"] as? String == "nova")
        #expect(jsonObject?["speed"] as? Double == 1.25)
        #expect(jsonObject?["response_format"] as? String == "opus")
        #expect(jsonObject?["instructions"] as? String == "Speak softly")
    }

    @Test("doGenerate reports warnings for unsupported options")
    func testWarningForUnsupportedOptions() async throws {
        let mockFetch: FetchFunction = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://api.openai.com/v1/audio/speech")!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "audio/mp3"]
            )!
            return FetchResponse(body: .data(speechAudioData), urlResponse: response)
        }

        let config = OpenAIConfig(
            provider: "openai.speech",
            url: { _ in "https://api.openai.com/v1/audio/speech" },
            headers: { [:] },
            fetch: mockFetch
        )

        let model = OpenAISpeechModel(modelId: "tts-1", config: config)

        let result = try await model.doGenerate(
            options: SpeechModelV3CallOptions(
                text: "Hello",
                outputFormat: "unknown-format",
                language: "fr"
            )
        )

        #expect(result.warnings.contains(.unsupportedSetting(setting: "outputFormat", details: "Unsupported output format: unknown-format. Using mp3 instead.")))
        #expect(result.warnings.contains(.unsupportedSetting(setting: "language", details: "OpenAI speech models do not support language selection. Language parameter \"fr\" was ignored.")))
    }
}

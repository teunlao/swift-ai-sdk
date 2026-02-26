import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AssemblyAIProvider

@Suite("AssemblyAIProvider")
struct AssemblyAIProviderTests {
    private actor RequestCapture {
        var requests: [URLRequest] = []
        func append(_ request: URLRequest) { requests.append(request) }
        func all() -> [URLRequest] { requests }
    }

    private static func encodeJSON(_ dict: [String: Any]) -> Data {
        try! JSONSerialization.data(withJSONObject: dict)
    }

    private static func makeResponse(url: URL, json: [String: Any]) -> FetchResponse {
        let body = encodeJSON(json)
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return FetchResponse(body: .data(body), urlResponse: response)
    }

    @Test("supports upstream createAssemblyAI alias")
    func supportsCreateAssemblyAIAlias() {
        let provider = createAssemblyAI(settings: AssemblyAIProviderSettings(apiKey: "test-key"))
        let model = provider.transcription(modelId: .best)
        #expect(model.provider == "assemblyai.transcription")
    }

    @Test("uses upstream AssemblyAI endpoints for upload and transcript")
    func usesUpstreamEndpoints() async throws {
        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.append(request)

            guard let url = request.url else {
                throw APICallError(message: "Missing URL", url: "<missing>", requestBodyValues: nil)
            }

            switch url.path {
            case "/v2/upload":
                return Self.makeResponse(
                    url: url,
                    json: ["upload_url": "https://cdn.example.com/audio.wav"]
                )
            case "/v2/transcript":
                return Self.makeResponse(
                    url: url,
                    json: [
                        "text": "ok",
                        "language_code": "en",
                        "audio_duration": 1,
                    ]
                )
            default:
                throw APICallError(message: "Unexpected path", url: url.absoluteString, requestBodyValues: nil)
            }
        }

        let provider = createAssemblyAI(settings: AssemblyAIProviderSettings(apiKey: "test-key", fetch: fetch))
        let model = provider.transcription(modelId: .best)

        _ = try await model.doGenerate(
            options: .init(audio: .binary(Data([0x01, 0x02])), mediaType: "audio/wav")
        )

        let urls = await capture.all().compactMap(\.url?.absoluteString)
        #expect(urls.count == 2)
        #expect(urls.first == "https://api.assemblyai.com/v2/upload")
        #expect(urls.last == "https://api.assemblyai.com/v2/transcript")
    }

    @Suite("auth behavior", .serialized)
    struct AuthBehaviorTests {
        @Test("missing API key throws LoadAPIKeyError at request time")
        func missingAPIKeyThrowsAtRequestTime() async throws {
            actor RequestCapture {
                var requests: [URLRequest] = []
                func append(_ request: URLRequest) { requests.append(request) }
                func count() -> Int { requests.count }
            }

            let original = getenv("ASSEMBLYAI_API_KEY").flatMap { String(validatingCString: $0) }
            defer {
                if let original {
                    setenv("ASSEMBLYAI_API_KEY", original, 1)
                } else {
                    unsetenv("ASSEMBLYAI_API_KEY")
                }
            }

            unsetenv("ASSEMBLYAI_API_KEY")

            let capture = RequestCapture()
            let fetch: FetchFunction = { request in
                await capture.append(request)
                let url = request.url ?? URL(string: "https://api.assemblyai.com/v2/upload")!
                return AssemblyAIProviderTests.makeResponse(url: url, json: ["upload_url": "https://cdn.example.com/audio.wav"])
            }

            let provider = createAssemblyAI(settings: AssemblyAIProviderSettings(fetch: fetch))
            let model = provider.transcription(modelId: .best)

            do {
                _ = try await model.doGenerate(
                    options: .init(audio: .binary(Data([0x01])), mediaType: "audio/wav")
                )
                Issue.record("Expected missing API key error")
            } catch let error as LoadAPIKeyError {
                #expect(error.message.contains("ASSEMBLYAI_API_KEY environment variable"))
            } catch {
                Issue.record("Expected LoadAPIKeyError, got: \(error)")
            }

            #expect(await capture.count() == 0)
        }
    }
}

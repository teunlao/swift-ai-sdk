import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("FalProvider")
struct FalProviderTests {
    private func makeHTTPResponse(url: URL, statusCode: Int, headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
    }

    private func jsonData(_ value: Any) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    @Test("creates image/speech/transcription models")
    func createsModels() throws {
        let provider = createFal(settings: .init(apiKey: "test-api-key"))

        let image = provider.image("fal-ai/flux/dev")
        let speech = provider.speech("fal-ai/minimax/speech-02-hd")
        let transcription = provider.transcription("wizper")

        #expect(image.provider == "fal.image")
        #expect(image.modelId == "fal-ai/flux/dev")
        #expect(image.specificationVersion == "v3")

        #expect(speech.provider == "fal.speech")
        #expect(speech.modelId == "fal-ai/minimax/speech-02-hd")
        #expect(speech.specificationVersion == "v3")

        #expect(transcription.provider == "fal.transcription")
        #expect(transcription.modelId == "wizper")
        #expect(transcription.specificationVersion == "v3")

        #expect((try provider.imageModel(modelId: "fal-ai/flux/dev") as? FalImageModel)?.modelId == "fal-ai/flux/dev")
        #expect((try provider.speechModel(modelId: "fal-ai/minimax/speech-02-hd") as? FalSpeechModel)?.modelId == "fal-ai/minimax/speech-02-hd")
        #expect((try provider.transcriptionModel(modelId: "wizper") as? FalTranscriptionModel)?.modelId == "wizper")
    }

    @Test("configures baseURL and headers for image requests")
    func configuresBaseURLAndHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let imageUrl = "https://cdn.fal.run/image.png"
        let postURL = "https://custom.fal.run/fal-ai/flux/dev"

        let postBody = try jsonData([
            "images": [
                [
                    "url": imageUrl,
                    "width": 1024,
                    "height": 1024,
                    "content_type": "image/png",
                ]
            ]
        ])

        let fetch: FetchFunction = { request in
            let url = request.url?.absoluteString ?? ""
            if url == postURL {
                await capture.store(request)
                return FetchResponse(
                    body: .data(postBody),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: [
                            "Content-Type": "application/json",
                            "x-request-id": "test-id"
                        ]
                    )
                )
            }

            if url == imageUrl {
                return FetchResponse(
                    body: .data(Data("image-bytes".utf8)),
                    urlResponse: makeHTTPResponse(
                        url: request.url!,
                        statusCode: 200,
                        headers: ["Content-Type": "image/png"]
                    )
                )
            }

            Issue.record("Unexpected URL: \(url)")
            throw CancellationError()
        }

        let provider = createFal(settings: .init(
            apiKey: "test-api-key",
            baseURL: "https://custom.fal.run/",
            headers: ["X-Custom-Header": "value"],
            fetch: fetch
        ))

        let model = provider.image("fal-ai/flux/dev")
        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A cute baby sea otter",
                n: 1,
                providerOptions: [:]
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == postURL)
        #expect(request.httpMethod == "POST")

        let normalizedHeaders = Dictionary(
            uniqueKeysWithValues: (request.allHTTPHeaderFields ?? [:]).map { ($0.key.lowercased(), $0.value) }
        )

        #expect(normalizedHeaders["authorization"] == "Key test-api-key")
        #expect(normalizedHeaders["x-custom-header"] == "value")
        #expect((normalizedHeaders["user-agent"] ?? "").contains("ai-sdk/fal/"))
        #expect(normalizedHeaders["content-type"] == "application/json")

        let json = try JSONDecoder().decode(JSONValue.self, from: body)
        #expect(json == .object([
            "prompt": .string("A cute baby sea otter"),
            "num_images": .number(1)
        ]))
    }

    @Test("throws NoSuchModelError for unsupported model kinds")
    func throwsForUnsupportedModels() throws {
        let provider = createFal(settings: .init(apiKey: "test-api-key"))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.languageModel(modelId: "some-id")
        }

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "some-id")
        }
    }
}

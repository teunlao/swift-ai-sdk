import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import GoogleProvider

private func makeImageConfig(fetch: @escaping FetchFunction) -> GoogleGenerativeAIImageModelConfig {
    GoogleGenerativeAIImageModelConfig(
        provider: "google.generative-ai",
        baseURL: "https://generativelanguage.googleapis.com/v1beta",
        headers: { ["x-goog-api-key": "test"] },
        fetch: fetch,
        currentDate: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
}

@Suite("GoogleGenerativeAIImageModel")
struct GoogleGenerativeAIImageModelTests {
    @Test("issues warnings for unsupported settings and maps response")
    func warningsAndResponse() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func value() -> URLRequest? { request }
        }

        let capture = RequestCapture()
        let responseJSON: [String: Any] = [
            "predictions": [
                ["bytesBase64Encoded": Data([0x01]).base64EncodedString()],
                ["bytesBase64Encoded": Data([0x02]).base64EncodedString()]
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/imagen-3.0-generate-002:predict")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = GoogleGenerativeAIImageModel(
            modelId: GoogleGenerativeAIImageModelId(rawValue: "imagen-3.0-generate-002"),
            settings: GoogleGenerativeAIImageSettings(),
            config: makeImageConfig(fetch: fetch)
        )

        let result = try await model.doGenerate(options: ImageModelV3CallOptions(
            prompt: "sunset",
            n: 2,
            size: "1024x1024",
            seed: 42,
            providerOptions: [
                "google": [
                    "personGeneration": .string("allow_all"),
                    "aspectRatio": .string("16:9")
                ]
            ]
        ))

        #expect(result.warnings.count == 2)
        if case let .base64(images) = result.images {
            #expect(images == [
                Data([0x01]).base64EncodedString(),
                Data([0x02]).base64EncodedString()
            ])
        } else {
            Issue.record("Expected base64 image payload")
        }
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 1_700_000_000))

        if let metadata = result.providerMetadata?["google"] {
            #expect(metadata.images.count == 2)
        } else {
            Issue.record("Expected provider metadata for google")
        }

        guard let request = await capture.value(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            Issue.record("Missing request payload")
            return
        }

        #expect(json["instances"] != nil)
        if let parameters = json["parameters"] as? [String: Any] {
            #expect(parameters["sampleCount"] as? Int == 2)
            // aspectRatio should be "16:9" from providerOptions (size is ignored)
            #expect(parameters["aspectRatio"] as? String == "16:9")
            #expect(parameters["personGeneration"] as? String == "allow_all")
        } else {
            Issue.record("Expected parameters object")
        }
    }
}

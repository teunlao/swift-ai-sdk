import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ProdiaProvider

@Suite("ProdiaProvider")
struct ProdiaProviderTests {
    private struct MultipartResponse: Sendable {
        let body: Data
        let contentType: String
    }

    private func createMultipartResponse(
        jobResult: [String: Any],
        imageContent: String = "test-image"
    ) throws -> MultipartResponse {
        let boundary = "test-boundary-12345"
        let jobJsonData = try JSONSerialization.data(withJSONObject: jobResult)
        let imageBuffer = Data(imageContent.utf8)

        var body = Data()
        func append(_ string: String) {
            body.append(Data(string.utf8))
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"job\"; filename=\"job.json\"\r\n")
        append("Content-Type: application/json\r\n")
        append("\r\n")
        body.append(jobJsonData)
        append("\r\n")
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"output\"; filename=\"output.png\"\r\n")
        append("Content-Type: image/png\r\n")
        append("\r\n")
        body.append(imageBuffer)
        append("\r\n--\(boundary)--\r\n")

        return MultipartResponse(
            body: body,
            contentType: "multipart/form-data; boundary=\(boundary)"
        )
    }

    @Test("creates image models via .image")
    func createsImageModels() throws {
        let provider = createProdiaProvider(settings: .init(apiKey: "test-api-key"))

        let imageModel = provider.image(modelId: .inferenceFluxFastSchnellTxt2imgV2)
        let imageModel2 = try provider.imageModel(modelId: ProdiaImageModelId.inferenceFluxSchnellTxt2imgV2.rawValue)

        #expect(imageModel.provider == "prodia.image")
        #expect(imageModel.modelId == "inference.flux-fast.schnell.txt2img.v2")
        #expect(imageModel2.modelId == "inference.flux.schnell.txt2img.v2")
        #expect(imageModel.specificationVersion == "v3")
    }

    @Test("configures baseURL and headers correctly")
    func configuresBaseURLAndHeaders() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()
        let multipart = try createMultipartResponse(jobResult: [
            "id": "job-123",
            "state": ["current": "completed"],
            "config": ["prompt": "test"],
        ])

        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.example.com/v2/job")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: [
                "Content-Type": multipart.contentType
            ]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(multipart.body), urlResponse: httpResponse)
        }

        let provider = createProdiaProvider(settings: .init(
            apiKey: "test-api-key",
            baseURL: "https://api.example.com/v2",
            headers: [
                "x-extra-header": "extra",
            ],
            fetch: fetch
        ))

        let model = provider.image(modelId: .inferenceFluxFastSchnellTxt2imgV2)

        _ = try await model.doGenerate(
            options: ImageModelV3CallOptions(
                prompt: "A serene mountain landscape at sunset",
                n: 1,
                size: nil,
                aspectRatio: nil,
                seed: nil,
                providerOptions: [:],
                abortSignal: nil,
                headers: nil,
                files: nil,
                mask: nil
            )
        )

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        let headers = (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }

        #expect(request.url?.absoluteString == "https://api.example.com/v2/job")
        #expect(request.httpMethod == "POST")
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["x-extra-header"] == "extra")
        #expect(headers["accept"] == "multipart/form-data; image/png")

        #expect((headers["user-agent"] ?? "").contains("ai-sdk/prodia/"))

        if let type = json["type"] as? String {
            #expect(type == "inference.flux-fast.schnell.txt2img.v2")
        } else {
            Issue.record("Missing type")
        }

        if let config = json["config"] as? [String: Any] {
            #expect(config["prompt"] as? String == "A serene mountain landscape at sunset")
        } else {
            Issue.record("Missing config")
        }
    }

    @Test("throws NoSuchModelError for unsupported model types")
    func throwsForUnsupportedTypes() throws {
        let provider = createProdiaProvider(settings: .init(apiKey: "test-api-key"))

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.languageModel(modelId: "some-id")
        }

        #expect(throws: NoSuchModelError.self) {
            _ = try provider.textEmbeddingModel(modelId: "some-id")
        }
    }
}


import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

@Suite("Compatible image downloads")
struct OpenAICompatibleImageDownloadTests {
    actor Capture {
        var authorization: String?
        func store(_ request: URLRequest) { authorization = request.value(forHTTPHeaderField: "Authorization") }
        func value() -> String? { authorization }
    }
    @Test(arguments: [true, false])
    func mixedImagesPreserveOrderAndScopeCredentials(sameOrigin: Bool) async throws {
        let capture = Capture()
        let endpoint = "https://api.example.com/v1/images/generations"
        let imageURL = sameOrigin ? "https://api.example.com/output.png" : "https://images.example.com/output.png"
        let response: JSONValue = ["data": [["b64_json": "AQI="], ["url": .string(imageURL)]], "usage": ["input_tokens": 1, "output_tokens": 2, "total_tokens": 3]]
        let responseData = try JSONEncoder().encode(response)
        let fetch: FetchFunction = { request in
            let data: Data
            if request.httpMethod == "GET" {
                await capture.store(request)
                data = Data([3, 4])
            } else { data = responseData }
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": request.httpMethod == "GET" ? "image/png" : "application/json"])!)
        }
        let model = OpenAICompatibleImageModel(modelId: .init(rawValue: "image"), config: .init(provider: "custom.image", headers: { ["Authorization": "Bearer secret"] }, url: { _ in endpoint }, fetch: fetch))
        let result = try await model.doGenerate(options: .init(prompt: "Image", n: 2))
        #expect(result.images == .binary([Data([1, 2]), Data([3, 4])]))
        #expect(await capture.value() == (sameOrigin ? "Bearer secret" : nil))
        #expect(result.usage?.inputTokens == 1)
        #expect(result.usage?.outputTokens == 2)
        #expect(result.usage?.totalTokens == 3)
    }
}

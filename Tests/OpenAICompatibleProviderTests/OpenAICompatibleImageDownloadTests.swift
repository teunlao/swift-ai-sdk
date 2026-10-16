import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

@Suite("Compatible image downloads")
struct OpenAICompatibleImageDownloadTests {
    actor Capture {
        var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func value() -> URLRequest? { request }
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
            } else {
                #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
                data = responseData
            }
            return FetchResponse(body: .data(data), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": request.httpMethod == "GET" ? "image/png" : "application/json"])!)
        }
        let model = OpenAICompatibleImageModel(modelId: .init(rawValue: "image"), config: .init(provider: "custom.image", headers: { ["Authorization": "Bearer secret", "X-API-Key": "secret", "Cookie": "secret=session"] }, url: { _ in endpoint }, fetch: fetch))
        let result = try await model.doGenerate(options: .init(prompt: "Image", n: 2))
        #expect(result.images == .binary([Data([1, 2]), Data([3, 4])]))
        let download = try #require(await capture.value())
        #expect(download.value(forHTTPHeaderField: "User-Agent") != nil)
        #expect((download.allHTTPHeaderFields ?? [:]).keys.allSatisfy { $0.lowercased() == "user-agent" })
        #expect(result.usage?.inputTokens == 1)
        #expect(result.usage?.outputTokens == 2)
        #expect(result.usage?.totalTokens == 3)
    }
}

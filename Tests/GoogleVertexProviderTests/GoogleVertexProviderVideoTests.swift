import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex video routing")
struct GoogleVertexProviderVideoTests {
    @Test(arguments: [("global", "aiplatform.googleapis.com"), ("eu", "aiplatform.eu.rep.googleapis.com"), ("us", "aiplatform.us.rep.googleapis.com"), ("us-central1", "us-central1-aiplatform.googleapis.com")])
    func regionalRouting(location: String, host: String) async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: location, project: "test-project", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"name":"operations/region"}"#)
        }, accessTokenProvider: { "token" }))
        let model = provider.video(modelId: .veo31Generate001)
        let result = try await model.doStart(options: .init(n: 1))
        #expect(result.operation == .object(["operationName": .string("operations/region")]))
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://\(host)/v1beta1/projects/test-project/locations/\(location)/publishers/google/models/veo-3.1-generate-001:predictLongRunning")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
    }
}

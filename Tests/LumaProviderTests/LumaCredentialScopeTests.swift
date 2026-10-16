import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import LumaProvider

@Suite("Luma credential scope")
struct LumaCredentialScopeTests {
    private actor Requests {
        var entries: [(url: String, authorization: String?)] = []
        func record(_ request: URLRequest) {
            entries.append((request.url!.absoluteString, request.value(forHTTPHeaderField: "Authorization")))
        }
        func authorization(for url: String) -> String?? {
            entries.first { $0.url == url }.map { $0.authorization }
        }
    }

    @Test("API requests carry the key and the generated-image download does not")
    func downloadCarriesNoKey() async throws {
        let apiBase = "https://api.lumalabs.ai/dream-machine/v1/generations"
        let imageURL = "https://cdn.example.net/image.png"
        let requests = Requests()

        let fetch: FetchFunction = { request in
            await requests.record(request)
            let url = request.url!.absoluteString
            let body: Data
            let contentType: String
            if url == imageURL {
                body = Data([1, 2, 3])
                contentType = "image/png"
            } else if url == "\(apiBase)/image" {
                body = Data(#"{"id":"gen-1","state":"queued"}"#.utf8)
                contentType = "application/json"
            } else {
                body = Data(#"{"id":"gen-1","state":"completed","assets":{"image":"\#(imageURL)"}}"#.utf8)
                contentType = "application/json"
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            return FetchResponse(body: .data(body), urlResponse: response)
        }

        let provider = createLuma(settings: .init(apiKey: "luma-secret", fetch: fetch))
        _ = try await provider.image(modelId: .photon1).doGenerate(
            options: .init(prompt: "A red kite", n: 1)
        )

        #expect(await requests.authorization(for: "\(apiBase)/image") == .some("Bearer luma-secret"))
        #expect(await requests.authorization(for: "\(apiBase)/gen-1") == .some("Bearer luma-secret"))
        #expect(await requests.authorization(for: imageURL) == .some(nil))
    }
}

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ReplicateProvider

@Suite("Replicate credential scope")
struct ReplicateCredentialScopeTests {
    private actor Requests {
        var entries: [(url: String, authorization: String?)] = []
        func record(_ request: URLRequest) {
            entries.append((request.url!.absoluteString, request.value(forHTTPHeaderField: "Authorization")))
        }
        func authorization(for url: String) -> String?? {
            entries.first { $0.url == url }.map { $0.authorization }
        }
    }

    @Test("API request carries the token and the output download does not")
    func downloadCarriesNoToken() async throws {
        let apiURL = "https://api.replicate.com/v1/models/black-forest-labs/flux-schnell/predictions"
        let outputURL = "https://cdn.example.net/out-0.webp"
        let requests = Requests()

        let fetch: FetchFunction = { request in
            await requests.record(request)
            let url = request.url!.absoluteString
            guard url == apiURL || url == outputURL else {
                Issue.record("Unexpected URL: \(url)")
                throw CancellationError()
            }
            let isOutput = url == outputURL
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": isOutput ? "image/webp" : "application/json"]
            )!
            return FetchResponse(
                body: .data(isOutput ? Data([1, 2, 3]) : Data(#"{"status":"succeeded","urls":{"get":"https://api.replicate.com/v1/predictions/id"},"output":["\#(outputURL)"]}"#.utf8)),
                urlResponse: response
            )
        }

        let provider = createReplicate(settings: .init(apiToken: "replicate-secret", fetch: fetch))
        _ = try await provider.image("black-forest-labs/flux-schnell").doGenerate(
            options: .init(prompt: "A cute baby sea otter", n: 1, providerOptions: [:])
        )

        #expect(await requests.authorization(for: apiURL) == .some("Bearer replicate-secret"))
        #expect(await requests.authorization(for: outputURL) == .some(nil))
    }
}

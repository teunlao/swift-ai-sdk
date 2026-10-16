import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import BlackForestLabsProvider

@Suite("Black Forest Labs credential scope")
struct BlackForestLabsCredentialScopeTests {
    private actor Requests {
        var entries: [(url: String, key: String?)] = []
        func record(_ request: URLRequest) {
            entries.append((request.url!.absoluteString, request.value(forHTTPHeaderField: "x-key")))
        }
        func key(forPrefix prefix: String) -> String?? {
            entries.first { $0.url.hasPrefix(prefix) }.map { $0.key }
        }
    }

    /// Runs one generation whose polling and image URLs point at `deliveryHost`.
    private func generate(deliveryHost: String, requests: Requests) async throws {
        let apiURL = "https://api.bfl.ai/v1/flux-pro-1.1"
        let pollURL = "https://\(deliveryHost)/poll"
        let imageURL = "https://\(deliveryHost)/image.png"

        let fetch: FetchFunction = { request in
            await requests.record(request)
            let url = request.url!.absoluteString
            let body: Data
            let contentType: String
            if url == apiURL {
                body = Data(#"{"id":"req-1","polling_url":"\#(pollURL)"}"#.utf8)
                contentType = "application/json"
            } else if url.hasPrefix(pollURL) {
                body = Data(#"{"status":"Ready","result":{"sample":"\#(imageURL)"}}"#.utf8)
                contentType = "application/json"
            } else if url == imageURL {
                body = Data([1, 2, 3])
                contentType = "image/png"
            } else {
                Issue.record("Unexpected URL: \(url)")
                throw CancellationError()
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": contentType]
            )!
            return FetchResponse(body: .data(body), urlResponse: response)
        }

        let provider = createBlackForestLabs(settings: .init(apiKey: "bfl-secret", fetch: fetch))
        _ = try await provider.image(.fluxPro11).doGenerate(
            options: .init(prompt: "A cute baby sea otter", n: 1, providerOptions: [:])
        )
    }

    @Test("a foreign delivery host receives no key from polling or download")
    func foreignHostReceivesNoKey() async throws {
        let requests = Requests()
        try await generate(deliveryHost: "cdn.example.net", requests: requests)

        #expect(await requests.key(forPrefix: "https://api.bfl.ai/v1/flux-pro-1.1") == .some("bfl-secret"))
        #expect(await requests.key(forPrefix: "https://cdn.example.net/poll") == .some(nil))
        #expect(await requests.key(forPrefix: "https://cdn.example.net/image.png") == .some(nil))
    }

    @Test("a sibling cluster host under bfl.ai keeps receiving the key")
    func siblingClusterHostReceivesKey() async throws {
        let requests = Requests()
        try await generate(deliveryHost: "api.us1.bfl.ai", requests: requests)

        #expect(await requests.key(forPrefix: "https://api.us1.bfl.ai/poll") == .some("bfl-secret"))
        #expect(await requests.key(forPrefix: "https://api.us1.bfl.ai/image.png") == .some("bfl-secret"))
    }
}

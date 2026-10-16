import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import FalProvider

@Suite("Fal credential scope")
struct FalCredentialScopeTests {
    private actor Requests {
        var entries: [(url: String, authorization: String?)] = []
        func record(_ request: URLRequest) {
            entries.append((request.url!.absoluteString, request.value(forHTTPHeaderField: "Authorization")))
        }
        func authorization(for url: String) -> String?? {
            entries.first { $0.url == url }.map { $0.authorization }
        }
    }

    private func makeFetch(
        requests: Requests,
        apiURL: String,
        apiBody: String,
        assetURL: String,
        assetContentType: String
    ) -> FetchFunction {
        { request in
            await requests.record(request)
            let url = request.url!.absoluteString
            let isAsset = url == assetURL
            guard isAsset || url == apiURL else {
                Issue.record("Unexpected URL: \(url)")
                throw CancellationError()
            }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": isAsset ? assetContentType : "application/json"]
            )!
            return FetchResponse(
                body: .data(isAsset ? Data([1, 2, 3]) : Data(apiBody.utf8)),
                urlResponse: response
            )
        }
    }

    @Test("image: API request carries the key and the image download does not")
    func imageDownloadCarriesNoKey() async throws {
        let assetURL = "https://cdn.example.net/image.png"
        let apiURL = "https://fal.run/fal-ai/flux/dev"
        let requests = Requests()
        let fetch = makeFetch(
            requests: requests,
            apiURL: apiURL,
            apiBody: #"{"images":[{"url":"\#(assetURL)","width":1,"height":1,"content_type":"image/png"}]}"#,
            assetURL: assetURL,
            assetContentType: "image/png"
        )

        let provider = createFal(settings: .init(apiKey: "fal-secret", fetch: fetch))
        _ = try await provider.image("fal-ai/flux/dev").doGenerate(
            options: .init(prompt: "A cute baby sea otter", n: 1, providerOptions: [:])
        )

        #expect(await requests.authorization(for: apiURL) == .some("Key fal-secret"))
        #expect(await requests.authorization(for: assetURL) == .some(nil))
    }

    @Test("speech: API request carries the key and the audio download does not")
    func speechDownloadCarriesNoKey() async throws {
        let assetURL = "https://cdn.example.net/speech.mp3"
        let apiURL = "https://fal.run/fal-ai/minimax/speech-02-hd"
        let requests = Requests()
        let fetch = makeFetch(
            requests: requests,
            apiURL: apiURL,
            apiBody: #"{"audio":{"url":"\#(assetURL)"}}"#,
            assetURL: assetURL,
            assetContentType: "audio/mpeg"
        )

        let provider = createFal(settings: .init(apiKey: "fal-secret", fetch: fetch))
        _ = try await provider.speech("fal-ai/minimax/speech-02-hd").doGenerate(
            options: .init(text: "Hello")
        )

        #expect(await requests.authorization(for: apiURL) == .some("Key fal-secret"))
        #expect(await requests.authorization(for: assetURL) == .some(nil))
    }

    @Test("response-supplied private image and audio URLs are rejected", arguments: [false, true])
    func rejectsPrivateDownload(speech: Bool) async throws {
        let assetURL = "http://127.0.0.1/private"
        let apiURL = speech ? "https://fal.run/fal-ai/minimax/speech-02-hd" : "https://fal.run/fal-ai/flux/dev"
        let requests = Requests()
        let fetch = makeFetch(
            requests: requests, apiURL: apiURL,
            apiBody: speech ? #"{"audio":{"url":"\#(assetURL)"}}"# : #"{"images":[{"url":"\#(assetURL)"}]}"#,
            assetURL: assetURL, assetContentType: "application/octet-stream"
        )
        let provider = createFal(settings: .init(apiKey: "fal-secret", fetch: fetch))
        await #expect(throws: DownloadError.self) {
            if speech {
                _ = try await provider.speech("fal-ai/minimax/speech-02-hd").doGenerate(options: .init(text: "Hello"))
            } else {
                _ = try await provider.image("fal-ai/flux/dev").doGenerate(options: .init(n: 1))
            }
        }
        #expect(await requests.authorization(for: apiURL) == .some("Key fal-secret"))
        #expect(await requests.authorization(for: assetURL) == nil)
    }
}

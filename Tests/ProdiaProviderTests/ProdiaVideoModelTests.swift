import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ProdiaProvider

@Suite("Prodia V4 video")
struct ProdiaVideoModelTests {
    private let fixture = ProdiaMultipartFixture(parts: [.init(name: "output", filename: "video.webm", mediaType: "video/webm", data: Data([0, 255, 1]))])

    @Test("text-to-video sends the job JSON and returns binary output with billing metadata")
    func textVideo() async throws {
        let fetch: FetchFunction = { request in
            #expect(request.url?.absoluteString == "https://example.com/v2/job?price=true")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            #expect(request.value(forHTTPHeaderField: "Accept") == "multipart/form-data; video/mp4")
            #expect(request.value(forHTTPHeaderField: "x-client") == "client")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
            let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody))
            #expect(body == .object([
                "type": .string("inference.wan2-2.lightning.txt2vid.v0"), "config": .object([
                    "prompt": .string("city"), "seed": .number(0), "resolution": .string("720p"),
                ]),
            ]))
            return fixture.response(request)
        }
        let model = createProdia(settings: .init(apiKey: "secret", baseURL: "https://example.com/v2/", fetch: fetch)).video(.wan22LightningTxt2vid)
        let result = try await model.doGenerate(options: .init(prompt: "city", n: 1, seed: 0,
            providerOptions: ["prodia": ["resolution": .string("720p"), "extra": .bool(true)]],
            headers: ["x-client": "client", "content-type": "text/plain", "accept": "text/plain"]))
        #expect(result.videos == [.binary(data: Data([0, 255, 1]), mediaType: "video/webm")])
        #expect(result.warnings.isEmpty)
        #expect(result.providerMetadata?["prodia"]?["videos"] == .array([.object([
            "jobId": .string("job"), "createdAt": .string("created"), "updatedAt": .string("updated"),
            "seed": .number(0), "elapsed": .number(1.5), "iterationsPerSecond": .number(2), "dollars": .number(0.01),
        ])]))
        #expect(result.response.headers?["x-request-id"] == "media-id")
    }

    @Test("image-to-video uploads binary and base64 inputs as multipart files", arguments: [false, true])
    func imageVideo(base64: Bool) async throws {
        let fetch: FetchFunction = { request in
            #expect(try ProdiaMultipartFixture.requestJob(request) == .object([
                "type": .string("inference.wan2-2.lightning.img2vid.v0"), "config": .object([:]),
            ]))
            let body = try #require(request.httpBody)
            #expect(body.range(of: Data("filename=\"input.png\"".utf8)) != nil)
            #expect(body.range(of: Data([1, 2, 3])) != nil)
            return fixture.response(request)
        }
        let model = createProdia(settings: .init(apiKey: "secret", fetch: fetch)).video(.wan22LightningImg2vid)
        let image: VideoModelV4File = .file(mediaType: "image/png", data: base64 ? .base64("AQID") : .binary(Data([1, 2, 3])), providerOptions: nil)
        let result = try await model.doGenerate(options: .init(n: 1, image: image))
        #expect(result.videos == [.binary(data: Data([0, 255, 1]), mediaType: "video/webm")])
    }

    @Test("URL input downloads use raw fetch without provider or request credentials")
    func downloadedInput() async throws {
        let fetch: FetchFunction = { request in
            if request.url?.host == "cdn.example.net" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "x-private") == nil)
                return .init(body: .data(Data([1, 2, 3])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/jpeg"])!)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            let body = try #require(request.httpBody)
            #expect(body.range(of: Data("filename=\"input.jpg\"".utf8)) != nil)
            return fixture.response(request)
        }
        let model = createProdia(settings: .init(apiKey: "secret", headers: ["x-private": "provider"], fetch: fetch)).video(.wan22LightningImg2vid)
        let result = try await model.doGenerate(options: .init(n: 1, image: .url(url: "https://cdn.example.net/input", providerOptions: nil), headers: ["x-private": "request"]))
        #expect(result.videos.count == 1)
    }

    @Test("private URL inputs are rejected before download")
    func privateURL() async throws {
        let model = createProdia(settings: .init(apiKey: "secret", fetch: { _ in throw CancellationError() })).video(.wan22LightningImg2vid)
        await #expect(throws: DownloadError.self) {
            _ = try await model.doGenerate(options: .init(n: 1, image: .url(url: "http://127.0.0.1/private", providerOptions: nil)))
        }
    }

    @Test("output selection supports unnamed video, last matching part and default mp4")
    func outputSelection() async throws {
        let response = ProdiaMultipartFixture(parts: [
            .init(name: "other", mediaType: "video/webm", data: Data([1])),
            .init(name: "output", mediaType: "application/octet-stream", data: Data([2])),
        ])
        let model = createProdia(settings: .init(apiKey: "secret", fetch: { response.response($0) })).video("custom")
        #expect(try await model.doGenerate(options: .init(n: 1)).videos == [.binary(data: Data([2]), mediaType: "video/webm")])
        let fallback = ProdiaMultipartFixture(parts: [.init(name: "output", mediaType: "application/octet-stream", data: Data())])
        let other = createProdia(settings: .init(apiKey: "secret", fetch: { fallback.response($0) })).video("custom")
        #expect(try await other.doGenerate(options: .init(n: 1)).videos == [.binary(data: Data(), mediaType: "video/mp4")])
    }

    @Test("missing multipart job or output retain HTTP error context", arguments: [false, true])
    func missingPart(job: Bool) async throws {
        let fixture = ProdiaMultipartFixture(job: job ? nil : #"{"id":"job"}"#, parts: [])
        let model = createProdia(settings: .init(apiKey: "secret", fetch: { fixture.response($0) })).video("custom")
        do {
            _ = try await model.doGenerate(options: .init(n: 1))
            Issue.record("Expected multipart response error")
        } catch let error as APICallError {
            #expect(error.message == "Failed to process successful response")
            #expect(error.statusCode == 200)
            #expect((error.cause as? InvalidResponseDataError)?.message == (job ? "Prodia multipart response missing job part" : "Prodia multipart response missing output video"))
        }
    }

    @Test("explicit null resolution is invalid, rather than omitted")
    func invalidOptions() async throws {
        let model = createProdia(settings: .init(apiKey: "secret")).video("custom")
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(n: 1, providerOptions: ["prodia": ["resolution": .null]]))
        }
    }
}

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ByteDanceProvider

@Suite("ByteDance Seedream images")
struct ByteDanceImageModelTests {
    private let baseURL = "https://api.example.com/v3"
    private let date = Date(timeIntervalSince1970: 1_704_067_200)

    private actor Capture {
        var request: URLRequest?
        func record(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private func response(_ request: URLRequest, status: Int = 200, body: String) -> FetchResponse {
        .init(body: .data(Data(body.utf8)), urlResponse: HTTPURLResponse(
            url: request.url!, statusCode: status, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "x-request-id": "image-id"]
        )!)
    }

    private func model(fetch: @escaping FetchFunction) -> ByteDanceImageModel {
        ByteDanceImageModel(modelId: .seedream45251128, config: .init(
            provider: "bytedance.image", baseURL: baseURL, headers: { ["Authorization": "Bearer key"] },
            fetch: fetch, currentDate: { date }
        ))
    }

    @Test("image factory sends editing inputs and all image options while forcing base64 output")
    func imageRequest() async throws {
        let capture = Capture()
        let provider = createByteDance(settings: .init(apiKey: "secret", baseURL: baseURL + "/",
                                                      headers: ["x-provider": "provider"], fetch: { request in
            await capture.record(request)
            #expect(request.httpMethod == "POST")
            return response(request, body: #"{"data":[{"b64_json":"AQID","url":"https://foreign.example/image.png"}]}"#)
        }))
        let model = try provider.imageModel(modelId: "seedream-4-5-251128")
        let result = try await model.doGenerate(options: .init(
            prompt: "base prompt", n: 3, size: "2048x2048", aspectRatio: "16:9", seed: 0,
            files: [
                .url(url: "https://example.com/reference.png", providerOptions: nil),
                .file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil),
            ], mask: .file(mediaType: "image/png", data: .base64("AAAA"), providerOptions: nil),
            providerOptions: ["bytedance": [
                "watermark": .bool(false), "outputFormat": .string("png"), "size": .string("2K"),
                "sequentialImageGeneration": .string("auto"), "maxImages": .number(3), "optimizePromptMode": .string("fast"),
                "prompt": .string("override prompt"), "response_format": .string("url"), "custom": .null,
            ]], headers: ["x-client": "client"]
        ))
        let request = try #require(await capture.current())
        #expect(request.url?.absoluteString == baseURL + "/images/generations")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
        #expect(request.value(forHTTPHeaderField: "x-provider") == "provider")
        #expect(request.value(forHTTPHeaderField: "x-client") == "client")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-bytedance/") == true)
        #expect(try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)) == .object([
            "model": .string("seedream-4-5-251128"), "prompt": .string("override prompt"),
            "image": .array([.string("https://example.com/reference.png"), .string("data:image/png;base64,AQID")]),
            "size": .string("2K"), "watermark": .bool(false), "output_format": .string("png"),
            "sequential_image_generation": .string("auto"), "sequential_image_generation_options": .object(["max_images": .number(3)]),
            "optimize_prompt_options": .object(["mode": .string("fast")]), "custom": .null, "response_format": .string("b64_json"),
        ]))
        #expect(result.images == .base64(["AQID"]))
        #expect(result.warnings.contains { if case .unsupported(feature: "aspectRatio", _) = $0 { true } else { false } })
        #expect(result.warnings.contains { if case .unsupported(feature: "seed", _) = $0 { true } else { false } })
        #expect(result.warnings.contains { if case .unsupported(feature: "mask", _) = $0 { true } else { false } })
    }

    @Test("single binary, base64 and URL inputs use a scalar image field", arguments: ["binary", "base64", "url"])
    func singleInput(kind: String) async throws {
        let capture = Capture()
        let model = model { request in
            await capture.record(request)
            return response(request, body: #"{"data":[{"b64_json":"AQID"}]}"#)
        }
        let file: ImageModelV4File
        switch kind {
        case "binary": file = .file(mediaType: "image/png", data: .binary(Data([1, 2, 3])), providerOptions: nil)
        case "base64": file = .file(mediaType: "image/png", data: .base64("AQID"), providerOptions: nil)
        default: file = .url(url: "https://example.com/image.png", providerOptions: nil)
        }
        _ = try await model.doGenerate(options: .init(n: 1, files: [file]))
        let request = try #require(await capture.current())
        #expect(try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)) == .object([
            "model": .string("seedream-4-5-251128"), "response_format": .string("b64_json"),
            "image": .string(kind == "url" ? "https://example.com/image.png" : "data:image/png;base64,AQID"),
        ]))
    }

    @Test("image responses preserve output order, usage and HTTP metadata")
    func imageResponse() async throws {
        let model = model { request in
            response(request, body: #"{"data":[{"b64_json":"AQID"},{"b64_json":"BAUG"}],"usage":{"output_tokens":10,"total_tokens":15,"input_tokens":5}}"#)
        }
        let result = try await model.doGenerate(options: .init(prompt: "storyboard", n: 1))
        #expect(result.images == .base64(["AQID", "BAUG"]))
        #expect(result.usage == .init(outputTokens: 10, totalTokens: 15))
        #expect(result.response.timestamp == date)
        #expect(result.response.modelId == "seedream-4-5-251128")
        #expect(result.response.headers?["x-request-id"] == "image-id")
    }

    @Test("empty image results and nullable usage remain valid responses", arguments: ["null", "{}", #"{"output_tokens":null,"total_tokens":null}"#])
    func nullableUsage(usage: String) async throws {
        let model = model { request in response(request, body: #"{"data":[],"usage":\#(usage)}"#) }
        let result = try await model.doGenerate(options: .init(n: 1))
        #expect(result.images == .base64([]))
        #expect(result.usage == (usage == "null" ? nil : .init()))
    }

    @Test("known models expose editing support without mask support", arguments: [
        "dola-seedream-5-0-pro-260628", "seedream-5-0-260128", "seedream-5-0-lite-260128",
        "seedream-4-5-251128", "seedream-4-0-250828", "custom/model",
    ])
    func capabilities(modelId: String) async throws {
        let model = createByteDance().image(ByteDanceImageModelId(rawValue: modelId))
        #expect(model.supportsFileInputs == (modelId == "custom/model" ? nil : true))
        #expect(model.supportsMaskInputs == (modelId == "custom/model" ? nil : false))
    }

    @Test("null options are omitted while unknown options retain nulls")
    func nullOptions() async throws {
        let capture = Capture()
        let model = model { request in
            await capture.record(request)
            return response(request, body: #"{"data":[]}"#)
        }
        _ = try await model.doGenerate(options: .init(n: 1, size: "", files: [], providerOptions: ["bytedance": [
            "watermark": .null, "outputFormat": .null, "size": .null, "sequentialImageGeneration": .null,
            "maxImages": .null, "optimizePromptMode": .null, "custom": .null,
        ]]))
        let request = try #require(await capture.current())
        #expect(try JSONDecoder().decode(JSONValue.self, from: #require(request.httpBody)) == .object([
            "model": .string("seedream-4-5-251128"), "size": .string(""), "custom": .null, "response_format": .string("b64_json"),
        ]))
    }

    @Test("invalid model options fail before submission", arguments: [
        ["maxImages": JSONValue.number(0)], ["maxImages": .number(1.5)], ["outputFormat": .string("webp")],
        ["sequentialImageGeneration": .string("batch")], ["optimizePromptMode": .string("slow")], ["watermark": .string("yes")],
    ])
    func invalidOptions(options: JSONObject) async throws {
        let model = model { _ in throw CancellationError() }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(n: 1, providerOptions: ["bytedance": options]))
        }
    }

    @Test("malformed successful responses fail at the HTTP boundary", arguments: [#"{}"#, #"{"data":[{"b64_json":3}]}"#, #"{"data":[{"url":"https://example.com/image.png"}]}"#])
    func invalidResponse(body: String) async throws {
        let model = model { request in response(request, body: body) }
        do {
            _ = try await model.doGenerate(options: .init(n: 1))
            Issue.record("Expected invalid response error")
        } catch let error as APICallError {
            #expect(error.message == "Invalid JSON response")
            #expect(error.statusCode == 200)
            #expect(error.url == baseURL + "/images/generations")
        }
    }

    @Test("image errors use nested message, top-level message and unknown-error fallback", arguments: [
        #"{"error":{"message":"nested","code":null},"message":"outer"}"#, #"{"message":"outer"}"#, #"{}"#,
    ])
    func apiErrors(body: String) async throws {
        let model = model { request in response(request, status: 400, body: body) }
        do {
            _ = try await model.doGenerate(options: .init(n: 1))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == (body.contains("nested") ? "nested" : body.contains("outer") ? "outer" : "Unknown error"))
            #expect(error.statusCode == 400)
            #expect(error.responseBody == body)
        }
    }

    @Test("unsupported provider model kinds fail with NoSuchModelError")
    func unsupportedModels() throws {
        let provider = createByteDance()
        #expect(throws: NoSuchModelError.self) { _ = try provider.languageModel(modelId: "model") }
        #expect(throws: NoSuchModelError.self) { _ = try provider.embeddingModel(modelId: "model") }
    }
}

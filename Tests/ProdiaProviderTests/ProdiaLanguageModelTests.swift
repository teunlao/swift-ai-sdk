import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import ProdiaProvider

@Suite("Prodia V4 multimodal language")
struct ProdiaLanguageModelTests {
    private let date = Date(timeIntervalSince1970: 0)
    private let fixture = ProdiaMultipartFixture(parts: [
        .init(name: "output", mediaType: "image/png", data: Data([1, 2, 3])),
        .init(name: "output", filename: "first.txt", mediaType: "text/plain", data: Data("first".utf8)),
        .init(name: "ignored", mediaType: "image/png", data: Data([9])),
        .init(name: "output", filename: "message.txt", mediaType: "application/octet-stream", data: Data("final".utf8)),
        .init(name: "output", mediaType: "image/jpeg", data: Data([4, 5, 6])),
    ])

    private func model(fetch: @escaping FetchFunction) -> ProdiaLanguageModel {
        ProdiaLanguageModel(modelId: .nanoBananaImg2imgV2, config: .init(
            provider: "prodia.language", baseURL: "https://inference.prodia.com/v2", headers: { ["Authorization": "Bearer secret"] },
            fetch: fetch, currentDate: { date }
        ))
    }

    @Test("factory combines the last system and user prompt and selects the first image in the last user message")
    func requestPrompt() async throws {
        let fetch: FetchFunction = { request in
            let job = try ProdiaMultipartFixture.requestJob(request)
            #expect(job == .object(["type": .string("inference.nano-banana.img2img.v2"), "config": .object([
                "prompt": .string("last system\nfirst\nsecond"), "include_messages": .bool(true), "aspect_ratio": .string("16:9"),
            ])]))
            #expect(request.url?.absoluteString == "https://example.com/v2/job?price=true")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer key")
            #expect(request.value(forHTTPHeaderField: "x-provider") == "provider")
            #expect(request.value(forHTTPHeaderField: "x-client") == "client")
            #expect(request.value(forHTTPHeaderField: "Accept") == "multipart/form-data")
            let body = try #require(request.httpBody)
            #expect(body.range(of: Data("filename=\"input.png\"".utf8)) != nil)
            #expect(body.range(of: Data([1, 2, 3])) != nil)
            return fixture.response(request)
        }
        let provider = createProdia(settings: .init(apiKey: "key", baseURL: "https://example.com/v2/", headers: ["x-provider": "provider"], fetch: fetch))
        let model = try provider.languageModel(modelId: "inference.nano-banana.img2img.v2")
        let result = try await model.doGenerate(options: .init(prompt: [
            .system(content: "old system", providerOptions: nil),
            .user(content: [.text(.init(text: "old user")), .file(.init(data: .data(Data([9])), mediaType: "image/jpeg"))], providerOptions: nil),
            .system(content: "last system", providerOptions: nil),
            .user(content: [.text(.init(text: "")), .text(.init(text: "first")), .text(.init(text: "second")),
                .file(.init(data: .base64("AQID"), mediaType: "image/png")),
                .file(.init(data: .reference(["prodia": "ignored"]), mediaType: "image/png")),
            ], providerOptions: nil),
            .assistant(content: [.text(.init(text: "ignored assistant"))], providerOptions: nil),
        ], headers: ["x-client": "client", "accept": "ignored"], providerOptions: ["prodia": ["aspectRatio": .string("16:9"), "extra": .bool(true)]]))
        #expect(result.content == [.text(.init(text: "final")), .file(.init(mediaType: "image/png", data: .data(Data([1, 2, 3])))), .file(.init(mediaType: "image/jpeg", data: .data(Data([4, 5, 6]))))])
        #expect(result.finishReason == .init(unified: .stop))
        #expect(result.usage == .init())
        #expect(result.providerMetadata?["prodia"]?["dollars"] == .number(0.01))
    }

    @Test("images in earlier user messages do not become the current input")
    func lastUserOnly() async throws {
        let fetch: FetchFunction = { request in
            let job = try ProdiaMultipartFixture.requestJob(request)
            #expect(job == .object(["type": .string("inference.nano-banana.img2img.v2"), "config": .object(["prompt": .string("latest"), "include_messages": .bool(true)])]))
            return fixture.response(request)
        }
        let result = try await model(fetch: fetch).doGenerate(options: .init(prompt: [
            .user(content: [.file(.init(data: .url(URL(string: "http://127.0.0.1/unused")!), mediaType: "image/png"))], providerOptions: nil),
            .user(content: [.text(.init(text: "latest"))], providerOptions: nil),
        ]))
        #expect(result.content.first == .text(.init(text: "final")))
    }

    @Test("top-level image MIME is detected from bytes, full MIME is preserved and unknown bytes default to PNG", arguments: ["image", "image/*", "image/jpeg", "unknown"])
    func inputMediaType(type: String) async throws {
        let bytes = type == "unknown" ? Data([1, 2, 3]) : Data([137, 80, 78, 71, 13, 10, 26, 10])
        let fetch: FetchFunction = { request in
            let body = try #require(request.httpBody)
            #expect(body.range(of: bytes) != nil)
            let expected = type == "image/jpeg" ? "image/jpeg" : "image/png"
            #expect(body.range(of: Data("Content-Type: \(expected)".utf8)) != nil)
            #expect(body.range(of: Data("filename=\"input\(type == "image/jpeg" ? ".jpg" : ".png")\"".utf8)) != nil)
            return fixture.response(request)
        }
        let result = try await model(fetch: fetch).doGenerate(options: .init(prompt: [
            .user(content: [.file(.init(data: .data(bytes), mediaType: type == "unknown" ? "image" : type))], providerOptions: nil),
        ]))
        #expect(result.response?.timestamp == date)
    }

    @Test("URL inputs are credential-free and preserve raw body semantics even for non-2xx responses")
    func urlInput() async throws {
        let fetch: FetchFunction = { request in
            if request.url?.host == "cdn.example.net" {
                #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
                #expect(request.value(forHTTPHeaderField: "x-private") == nil)
                return .init(body: .data(Data([1, 2, 3])), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: ["Content-Type": "text/plain"])!)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer secret")
            let body = try #require(request.httpBody)
            #expect(body.range(of: Data([1, 2, 3])) != nil)
            return fixture.response(request)
        }
        let provider = createProdia(settings: .init(apiKey: "secret", headers: ["x-private": "provider"], fetch: fetch))
        let result = try await provider.languageModel(.nanoBananaImg2imgV2).doGenerate(options: .init(prompt: [
            .user(content: [.file(.init(data: .url(URL(string: "https://cdn.example.net/input")!), mediaType: "image/jpeg"))], providerOptions: nil),
        ], headers: ["x-private": "request"]))
        #expect(result.content.count == 3)
    }

    @Test("private image URLs are rejected by the download trust boundary")
    func privateURL() async throws {
        let model = model { _ in throw CancellationError() }
        await #expect(throws: DownloadError.self) {
            _ = try await model.doGenerate(options: .init(prompt: [.user(content: [
                .file(.init(data: .url(URL(string: "http://127.0.0.1/input")!), mediaType: "image/png")),
            ], providerOptions: nil)]))
        }
    }

    @Test("provider references and text file inputs fail with typed unsupported errors", arguments: [false, true])
    func unsupportedFiles(text: Bool) async throws {
        let model = model { _ in throw CancellationError() }
        do {
            _ = try await model.doGenerate(options: .init(prompt: [.user(content: [
                .file(.init(data: text ? .text("image") : .reference(["prodia": "file"]), mediaType: "image/png")),
            ], providerOptions: nil)]))
            Issue.record("Expected unsupported file failure")
        } catch let error as UnsupportedFunctionalityError {
            #expect(error.functionality == (text ? "text file parts" : "file parts with provider references"))
        }
    }

    @Test("unsupported settings produce ordered warnings while provider defaults remain quiet", arguments: [false, true])
    func warnings(custom: Bool) async throws {
        let model = model { fixture.response($0) }
        let result = try await model.doGenerate(options: .init(prompt: [],
            maxOutputTokens: custom ? 0 : nil, temperature: custom ? 0 : nil, stopSequences: custom ? [] : nil,
            topP: custom ? 0 : nil, topK: custom ? 0 : nil, presencePenalty: custom ? 0 : nil, frequencyPenalty: custom ? 0 : nil,
            responseFormat: custom ? .json(schema: nil, name: nil, description: nil) : .text, seed: custom ? 0 : nil,
            tools: custom ? [.function(.init(name: "tool", inputSchema: .object([:])))] : [], toolChoice: custom ? .auto : nil,
            reasoning: custom ? .some(.none) : .providerDefault
        ))
        let features = result.warnings.compactMap { warning -> String? in if case .unsupported(let feature, _) = warning { return feature }; return nil }
        #expect(features == (custom ? ["temperature", "topP", "topK", "seed", "maxOutputTokens", "stopSequences", "presencePenalty", "frequencyPenalty", "tools", "toolChoice", "responseFormat", "reasoning"] : []))
    }

    @Test("streaming wraps the generated multimodal result in the exact V4 event order")
    func streamResult() async throws {
        let result = try await model(fetch: { fixture.response($0) }).doStream(options: .init(prompt: [], temperature: 0))
        var events: [LanguageModelV4StreamPart] = []
        for try await event in result.stream { events.append(event) }
        #expect(events.count == 8)
        guard events.count == 8, case .textStart(let id, _) = events[2] else { Issue.record("Expected text-start event"); return }
        #expect(!id.isEmpty)
        #expect(Array(events.prefix(7)) == [
            .streamStart(warnings: [.unsupported(feature: "temperature", details: nil)]),
            .responseMetadata(id: nil, modelId: "inference.nano-banana.img2img.v2", timestamp: date),
            .textStart(id: id, providerMetadata: nil), .textDelta(id: id, delta: "final", providerMetadata: nil),
            .textEnd(id: id, providerMetadata: nil),
            .file(.init(mediaType: "image/png", data: .data(Data([1, 2, 3])))),
            .file(.init(mediaType: "image/jpeg", data: .data(Data([4, 5, 6])))),
        ])
        guard case .finish(let reason, let usage, let metadata) = events[7] else { Issue.record("Expected finish event"); return }
        #expect(reason == .init(unified: .stop))
        #expect(usage == .init())
        #expect(metadata?["prodia"]?["jobId"] == .string("job"))
        #expect(result.response?.headers?["x-request-id"] == "media-id")
    }

    @Test("language responses may contain no output parts or empty text", arguments: [false, true])
    func emptyOutput(text: Bool) async throws {
        let response = ProdiaMultipartFixture(parts: text ? [.init(name: "output", mediaType: "text/plain", data: Data())] : [])
        let result = try await model(fetch: { response.response($0) }).doGenerate(options: .init(prompt: []))
        #expect(result.content == (text ? [.text(.init(text: ""))] : []))
    }

    @Test("invalid and null provider aspect ratios fail before HTTP", arguments: [JSONValue.null, .string("5:9"), .number(1)])
    func invalidOptions(value: JSONValue) async throws {
        let model = model { _ in throw CancellationError() }
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: [], providerOptions: ["prodia": ["aspectRatio": value]]))
        }
    }

    @Test("API errors are thrown before a stream is returned")
    func apiError() async throws {
        let model = model { request in
            .init(body: .data(Data(#"{"detail":{"reason":"quota"}}"#.utf8)), urlResponse: HTTPURLResponse(url: request.url!, statusCode: 429, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!)
        }
        do {
            _ = try await model.doStream(options: .init(prompt: []))
            Issue.record("Expected API error")
        } catch let error as APICallError {
            #expect(error.message == #"{"reason":"quota"}"#)
            #expect(error.statusCode == 429)
            #expect(error.isRetryable)
        }
    }
}

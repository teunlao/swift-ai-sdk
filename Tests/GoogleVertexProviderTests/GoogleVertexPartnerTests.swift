import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex partner providers V4")
struct GoogleVertexPartnerTests {
    private let prompt: LanguageModelV4Prompt = [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]

    @Test func anthropicRequestTransformAndLabels() async throws {
        let requests = VertexRequests()
        let fixture = try vertexFixture("anthropic-partner.json")
        let provider = createGoogleVertexAnthropic(settings: .init(project: "project", location: "eu", headers: ["Authorization": "Bearer configured"], fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, fixture)
        }, generateAuthToken: { "generated" }))
        let model = try provider.languageModel(modelId: "claude-sonnet-4-5@20250929")
        #expect(try await model.supportedUrls.isEmpty)
        let schema: JSONValue = .object(["type": .string("object"), "properties": .object(["answer": .object(["type": .string("string")])])])
        let result = try await model.doGenerate(options: .init(
            prompt: prompt, responseFormat: .json(schema: schema, name: nil, description: nil),
            tools: [.function(.init(name: "weather", inputSchema: schema, strict: true))],
            headers: ["authorization": "Bearer request"], providerOptions: ["vertex": ["labels": .object(["team": .string("команда"), "env": .string("test")])]]
        ))
        #expect(result.content.contains { if case .text(let value) = $0 { return value.text == "answer" }; return false })
        #expect(result.usage.inputTokens.total == 10)
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://aiplatform.eu.rep.googleapis.com/v1/projects/project/locations/eu/publishers/anthropic/models/claude-sonnet-4-5@20250929:rawPredict")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer request")
        let labelString = try #require(request.value(forHTTPHeaderField: "x-vertex-ai-labels"))
        let labels = try #require(Data(base64Encoded: labelString))
        #expect(try JSONDecoder().decode([String: String].self, from: labels) == ["team": "команда", "env": "test"])
        guard case .object(let body) = try vertexBody(request) else { Issue.record("Missing Anthropic body"); return }
        #expect(body["model"] == nil)
        #expect(body["anthropic_version"] == .string("vertex-2023-10-16"))
        #expect(body["output_config"] == nil)
        guard case .array(let tools) = body["tools"] else { Issue.record("Missing JSON fallback tool"); return }
        #expect(tools.contains { if case .object(let tool) = $0 { return tool["name"] == .string("json") }; return false })
        #expect(tools.allSatisfy { if case .object(let tool) = $0 { return tool["strict"] == nil }; return false })
    }

    @Test func anthropicExplicitLabelsAndValidation() async throws {
        let requests = VertexRequests()
        let fixture = try vertexFixture("anthropic-partner.json")
        let provider = createGoogleVertexAnthropic(settings: .init(location: "unused invalid region", baseURL: "https://proxy.example/anthropic/", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, fixture)
        }))
        let model = provider.messages(modelId: "claude-sonnet-4-5@20250929")
        _ = try await model.doGenerate(options: .init(prompt: prompt, headers: ["X-vErTeX-Ai-LaBeLs": "explicit"], providerOptions: ["vertex": ["labels": .object(["team": .string("ignored")])]]))
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://proxy.example/anthropic/claude-sonnet-4-5@20250929:rawPredict")
        #expect(request.value(forHTTPHeaderField: "x-vertex-ai-labels") == "explicit")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        await #expect(throws: InvalidArgumentError.self) {
            _ = try await model.doGenerate(options: .init(prompt: prompt, providerOptions: ["vertex": ["labels": .object(["team": .number(1)])]]))
        }
    }

    @Test(arguments: [
        ("meta/llama-4-maverick-17b-128e-instruct-maas", nil as Int?, 8192 as Int?),
        ("meta/llama-4-scout-17b-16e-instruct-maas", nil, 8192),
        ("meta/llama-4-maverick-17b-128e-instruct-maas", 32, 32),
        ("deepseek-ai/deepseek-v3.2-maas", nil, nil)
    ])
    func maasChatDefaults(modelId: String, limit: Int?, expected: Int?) async throws {
        let requests = VertexRequests()
        let fixture = try vertexFixture("openai-partner.json")
        let provider = createGoogleVertexMaas(settings: .init(project: "project", headers: ["x-owner": "provider"], fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, fixture)
        }, generateAuthToken: { "oauth" }))
        let result = try await provider.languageModel(modelId: modelId).doGenerate(options: .init(prompt: prompt, maxOutputTokens: limit, headers: ["x-owner": "request", "Authorization": "Bearer overridden"]))
        #expect(result.content.contains { if case .text(let value) = $0 { return value.text == "answer" }; return false })
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1/projects/project/locations/global/endpoints/openapi/chat/completions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oauth")
        #expect(request.value(forHTTPHeaderField: "x-owner") == "provider")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-openai-compatible/") == true)
        guard case .object(let body) = try vertexBody(request) else { Issue.record("Missing compatible body"); return }
        #expect(body["model"] == .string(modelId))
        #expect(body["max_tokens"] == expected.map { .number(Double($0)) })
    }

    @Test func maasCompletionEmbeddingAndImages() async throws {
        let requests = VertexRequests()
        let completion = try vertexFixture("maas-completion.json")
        let embedding = try vertexFixture("maas-embedding.json")
        let image = try vertexFixture("maas-image.json")
        let provider = createGoogleVertexMaas(settings: .init(location: "unused invalid region", baseURL: "https://proxy.example/openapi/", fetch: { request in
            await requests.append(request)
            let path = request.url?.path ?? ""
            return try vertexResponse(request, path.hasSuffix("/embeddings") ? embedding : path.hasSuffix("/images/generations") ? image : completion)
        }))
        let text = try await provider.completionModel(modelId: "completion-model").doGenerate(options: .init(prompt: prompt))
        #expect(text.content.contains { if case .text(let value) = $0 { return value.text == "completion" }; return false })
        let vectors = try await provider.embeddingModel(modelId: "embedding-model").doEmbed(options: .init(values: ["hello"]))
        #expect(vectors.embeddings == [[0.1, 0.2]])
        let images = try await provider.imageModel(modelId: "image-model").doGenerate(options: .init(prompt: "sunset", n: 1))
        #expect(images.images == .base64(["AQID"]))
        let captured = await requests.values
        #expect(captured.map { $0.url?.path } == ["/openapi/completions", "/openapi/embeddings", "/openapi/images/generations"])
        #expect(captured.allSatisfy { $0.value(forHTTPHeaderField: "Authorization") == nil })
    }

    @Test func xaiRequestCapabilitiesAndUsage() async throws {
        let requests = VertexRequests()
        let fixture = try vertexFixture("openai-partner.json")
        let provider = createGoogleVertexXai(settings: .init(project: "project", location: "us-central1", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, fixture)
        }, generateAuthToken: { "oauth" }))
        let model = try provider.languageModel(modelId: "xai/grok-4.20-reasoning")
        let result = try await model.doGenerate(options: .init(prompt: prompt, responseFormat: .json(schema: .object(["type": .string("object")]), name: "answer", description: nil), reasoning: .high))
        #expect(result.usage.inputTokens == .init(total: 10, noCache: 7, cacheRead: 3))
        #expect(result.usage.outputTokens == .init(total: 9, text: 5, reasoning: 4))
        guard case .object(let raw) = result.usage.raw else { Issue.record("Missing raw usage"); return }
        #expect(raw["future_usage"] == .number(12))
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1/projects/project/locations/us-central1/endpoints/openapi/chat/completions")
        #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-openai-compatible/") == true)
        guard case .object(let body) = try vertexBody(request), case .object(let format) = body["response_format"] else { Issue.record("Missing JSON schema request"); return }
        #expect(body["reasoning_effort"] == nil)
        #expect(format["type"] == .string("json_schema"))
        let supported = try await model.supportedUrls
        let patterns = try #require(supported["image/*"])
        let url = "https://example.com/image.png"
        #expect(patterns.contains { $0.firstMatch(in: url, range: NSRange(url.startIndex..<url.endIndex, in: url)) != nil })
    }

    @Test func xaiStreamingUsage() async throws {
        let requests = VertexRequests()
        let events = try vertexFixture("xai-partner.sse")
        let provider = createGoogleVertexXai(settings: .init(baseURL: "https://proxy.example/openapi", fetch: { request in
            await requests.append(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "text/event-stream"])!
            return .init(body: .stream(AsyncThrowingStream { $0.yield(Data(events.utf8)); $0.finish() }), urlResponse: response)
        }))
        let result = try await provider.chatModel(modelId: "xai/grok-4.20-reasoning").doStream(options: .init(prompt: prompt, reasoning: .high))
        var text = ""
        var usage: LanguageModelV4Usage?
        for try await part in result.stream {
            if case .textDelta(_, let delta, _) = part { text += delta }
            if case .finish(_, let value, _) = part { usage = value }
        }
        #expect(text == "answer")
        #expect(usage?.outputTokens.total == 9)
        let request = try #require(await requests.last)
        guard case .object(let body) = try vertexBody(request) else { Issue.record("Missing stream body"); return }
        #expect(body["reasoning_effort"] == nil)
        #expect(body["stream_options"] == .object(["include_usage": .bool(true)]))
    }

    @Test func unsupportedModelsAndUnsafeRegionalHosts() async throws {
        let anthropic = createGoogleVertexAnthropic(settings: .init(project: "project", location: "evil.example/#"))
        let maas = createGoogleVertexMaas(settings: .init(project: "project", location: "region\n"))
        let providers: [any ProviderV4] = [anthropic, maas]
        for provider in providers {
            let model = try provider.languageModel(modelId: "model")
            await #expect(throws: InvalidArgumentError.self) { _ = try await model.doGenerate(options: .init(prompt: prompt)) }
        }
        let xai = createGoogleVertexXai()
        #expect(throws: NoSuchModelError.self) { _ = try xai.embeddingModel(modelId: "missing") }
        #expect(throws: NoSuchModelError.self) { _ = try xai.imageModel(modelId: "missing") }
        #expect(throws: NoSuchModelError.self) { _ = try anthropic.embeddingModel(modelId: "missing") }
        #expect(throws: NoSuchModelError.self) { _ = try anthropic.imageModel(modelId: "missing") }
    }
}

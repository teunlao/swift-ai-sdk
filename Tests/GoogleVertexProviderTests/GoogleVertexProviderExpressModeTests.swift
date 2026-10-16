import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import GoogleVertexProvider

@Suite("Vertex provider routing and authentication")
struct GoogleVertexProviderExpressModeTests {
    @Test func expressModeOverridesAPIKey() async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(apiKey: "KEY", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"embedding":{"values":[0.5]}}"#)
        }))
        let result = try await provider.embeddingModel(modelId: "gemini-embedding-2").doEmbed(options: .init(values: ["value"], headers: ["X-Goog-Api-Key": "WRONG"]))
        #expect(result.embeddings == [[0.5]])
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://aiplatform.googleapis.com/v1/publishers/google/models/gemini-embedding-2:embedContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "KEY")
    }

    @Test(arguments: ["evil.example.com/#", "user@localhost:8080/#", "us-central1\n", "-region", String(repeating: "a", count: 64)])
    func refusesInvalidLocation(location: String) async throws {
        let provider = createGoogleVertex(settings: .init(location: location, project: "project", fetch: { _ in throw CancellationError() }))
        let model = try provider.embeddingModel(modelId: "text-embedding-005")
        await #expect(throws: InvalidArgumentError.self) { _ = try await model.doEmbed(options: .init(values: ["value"])) }
    }

    @Test func customEndpointDoesNotLoadLocation() async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: "invalid/location", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"embedding":{"values":[0.5]}}"#)
        }, baseURL: "https://custom.example/"))
        let result = try await provider.embeddingModel(modelId: "gemini-embedding-2").doEmbed(options: .init(values: ["value"]))
        #expect(result.embeddings == [[0.5]])
        #expect(await requests.last?.url?.absoluteString == "https://custom.example/models/gemini-embedding-2:embedContent")
    }

    @Test func tunedEndpointAndNamespace() async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: "eu", project: "project", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"candidates":[{"content":{"parts":[{"text":"answer","thoughtSignature":"signature"}]},"finishReason":"STOP"}],"usageMetadata":{"promptTokenCount":1}}"#)
        }, accessTokenProvider: { "token" }))
        let model = try provider.languageModel(modelId: "endpoints/tuned-123")
        let result = try await model.doGenerate(options: .init(prompt: [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)], providerOptions: [
            "googleVertex": ["thinkingConfig": .object(["thinkingBudget": .number(512)])],
            "vertex": ["thinkingConfig": .object(["thinkingBudget": .number(128)])]
        ]))
        #expect(result.providerMetadata?["googleVertex"] == result.providerMetadata?["vertex"])
        #expect(result.providerMetadata?["googleVertex"] != nil)
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://aiplatform.eu.rep.googleapis.com/v1beta1/projects/project/locations/eu/endpoints/tuned-123:generateContent")
        guard case .object(let body) = try vertexBody(request), case .object(let generation) = body["generationConfig"] else { Issue.record("Missing generation config"); return }
        #expect(generation["thinkingConfig"] == .object(["thinkingBudget": .number(512)]))
    }

    @Test func interactionsUseLocationResource() async throws {
        let requests = VertexRequests()
        let provider = createGoogleVertex(settings: .init(location: "us", project: "project", fetch: { request in
            await requests.append(request)
            return try vertexResponse(request, #"{"id":"interaction-1","status":"completed","steps":[{"type":"model_output","content":[{"type":"text","text":"answer"}]}]}"#)
        }, accessTokenProvider: { "token" }))
        let model = provider.interactions(.managedAgent("managed-agent"))
        let result = try await model.doGenerate(options: .init(prompt: [.user(content: [.text(.init(text: "hello"))], providerOptions: nil)]))
        #expect(result.content.contains { if case .text(let value) = $0 { return value.text == "answer" }; return false })
        let request = try #require(await requests.last)
        #expect(request.url?.absoluteString == "https://aiplatform.us.rep.googleapis.com/v1beta1/projects/project/locations/us/interactions")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
        guard case .object(let body) = try vertexBody(request) else { Issue.record("Missing interaction body"); return }
        #expect(body["agent"] == .string("managed-agent"))
    }

    @Test func tunedEndpointRejectsExpressMode() async throws {
        let provider = createGoogleVertex(settings: .init(apiKey: "key", fetch: { _ in throw CancellationError() }))
        let model = try provider.languageModel(modelId: "endpoints/tuned-123")
        await #expect(throws: InvalidArgumentError.self) { _ = try await model.doGenerate(options: .init(prompt: [])) }
    }
}

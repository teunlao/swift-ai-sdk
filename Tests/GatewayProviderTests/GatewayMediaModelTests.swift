import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import GatewayProvider

@Suite("Gateway media models")
struct GatewayMediaModelTests {
    @Test("speech forwards controls and preserves provider usage and warnings")
    func speechGeneration() async throws {
        let provider = createGateway(settings: .init(apiKey: "key", teamIdOrSlug: "team", fetch: { request in
            #expect(request.url?.absoluteString == "https://ai-gateway.vercel.sh/v4/ai/speech-model")
            #expect(request.value(forHTTPHeaderField: "ai-speech-model-specification-version") == "4")
            #expect(request.value(forHTTPHeaderField: "x-vercel-ai-gateway-team") == "team")
            #expect(request.value(forHTTPHeaderField: "User-Agent")?.contains("ai-sdk-gateway/") == true)
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(body["text"] as? String == "Hello")
            #expect(body["voice"] as? String == "alloy")
            #expect(body["speed"] as? Double == 0)
            #expect(body["outputFormat"] as? String == "wav")
            #expect(body["instructions"] as? String == "Calm")
            #expect(body["language"] as? String == "en")
            return try response(request, #"{"audio":"AQID","usage":{"characters":5},"warnings":[{"type":"compatibility","feature":"speed"}],"providerMetadata":{"gateway":{"cost":"0.01"}}}"#)
        }))
        let result = try await provider.speech(modelId: "openai/tts-1").doGenerate(options: .init(
            text: "Hello", voice: "alloy", outputFormat: "wav", instructions: "Calm", speed: 0, language: "en"
        ))
        #expect(result.audio == .base64("AQID"))
        #expect(result.usage?["characters"] == .number(5))
        #expect(result.providerMetadata?["gateway"]?["cost"] == .string("0.01"))
        #expect(result.warnings == [.compatibility(feature: "speed", details: nil)])
        #expect(result.response.modelId == "openai/tts-1")
    }

    @Test("reranking preserves object documents and ranking indices")
    func reranking() async throws {
        let provider = createGateway(settings: .init(apiKey: "key", fetch: { request in
            #expect(request.url?.path == "/v4/ai/reranking-model")
            #expect(request.value(forHTTPHeaderField: "ai-reranking-model-specification-version") == "4")
            let data = try #require(request.httpBody)
            let body = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let documents = try #require(body["documents"] as? [String: Any])
            #expect(documents["type"] as? String == "object")
            let values = try #require(documents["values"] as? [[String: String]])
            #expect(values == [["title": "Rain"], ["title": "Sun"]])
            #expect(body["topN"] as? Int == 1)
            #expect(body["query"] as? String == "weather")
            return try response(request, #"{"ranking":[{"index":1,"relevanceScore":0.9}],"providerMetadata":{"gateway":{"cost":"0.02"}},"warnings":[{"type":"deprecated","setting":"old","message":"use new"}]}"#)
        }))
        let result = try await provider.reranking(modelId: "cohere/rerank-v3.5").doRerank(options: .init(
            documents: .object(values: [["title": .string("Rain")], ["title": .string("Sun")]]), query: "weather", topN: 1
        ))
        #expect(result.ranking == [.init(index: 1, relevanceScore: 0.9)])
        #expect(result.providerMetadata?["gateway"]?["cost"] == .string("0.02"))
        #expect(result.warnings == [.deprecated(setting: "old", message: "use new")])
    }

    private func response(_ request: URLRequest, _ body: String) throws -> FetchResponse {
        let url = try #require(request.url)
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"]))
        return FetchResponse(body: .data(Data(body.utf8)), urlResponse: response)
    }
}

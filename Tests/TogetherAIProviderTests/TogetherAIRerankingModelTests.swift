import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import TogetherAIProvider

@Suite("TogetherAIRerankingModel")
struct TogetherAIRerankingModelTests {
    @Test("doRerank builds request and maps response (object documents)")
    func doRerankObjectDocuments() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()

        let responseJSON: [String: Any] = [
            "id": "rerank-id",
            "model": "Salesforce/Llama-Rank-v1",
            "results": [
                ["index": 0, "relevance_score": 0.6475887154399037],
                ["index": 5, "relevance_score": 0.6323295373206566],
            ],
            "usage": [
                "prompt_tokens": 2966,
                "completion_tokens": 0,
                "total_tokens": 2966,
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.together.xyz/v1/rerank")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "Content-Length": "304"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = TogetherAIRerankingModel(
            modelId: .salesforceLlamaRankV1,
            config: .init(
                provider: "togetherai.reranking",
                baseURL: "https://api.together.xyz/v1",
                headers: { ["authorization": "Bearer test-api-key"] },
                fetch: fetch
            )
        )

        let documents: [JSONObject] = [
            ["example": .string("sunny day at the beach")],
            ["example": .string("rainy day in the city")],
        ]

        let result = try await model.doRerank(
            options: RerankingModelV3CallOptions(
                documents: .object(values: documents),
                query: "rainy day",
                topN: 2,
                providerOptions: [
                    "togetherai": [
                        "rankFields": .array([.string("example")])
                    ]
                ]
            )
        )

        #expect(result.ranking == [
            RerankingModelV3Ranking(index: 0, relevanceScore: 0.6475887154399037),
            RerankingModelV3Ranking(index: 5, relevanceScore: 0.6323295373206566),
        ])

        guard let response = result.response else {
            Issue.record("Expected response info")
            return
        }

        #expect(response.id == "rerank-id")
        #expect(response.modelId == "Salesforce/Llama-Rank-v1")
        #expect(response.headers?["content-type"] == "application/json")
        #expect(response.headers?["content-length"] == "304")

        #expect(result.providerMetadata == nil)
        #expect(result.warnings.isEmpty)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.together.xyz/v1/rerank")
        #expect(json["model"] as? String == "Salesforce/Llama-Rank-v1")
        #expect(json["query"] as? String == "rainy day")
        #expect(json["top_n"] as? Double == 2)
        #expect(json["return_documents"] as? Bool == false)

        if let rankFields = json["rank_fields"] as? [String] {
            #expect(rankFields == ["example"])
        } else {
            Issue.record("Expected rank_fields")
        }

        if let docs = json["documents"] as? [[String: Any]],
           let first = docs.first,
           first["example"] as? String == "sunny day at the beach" {
            #expect(true)
        } else {
            Issue.record("Expected documents array")
        }

        let headerFields = request.allHTTPHeaderFields ?? [:]
        let headers = headerFields.reduce(into: [String: String]()) { result, entry in
            result[entry.key.lowercased()] = entry.value
        }
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["content-type"] == "application/json")
    }

    @Test("doRerank builds request and maps response (text documents)")
    func doRerankTextDocuments() async throws {
        actor Capture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = Capture()

        let responseJSON: [String: Any] = [
            "id": "rerank-id",
            "model": "Salesforce/Llama-Rank-v1",
            "results": [
                ["index": 0, "relevance_score": 0.6475887154399037],
                ["index": 5, "relevance_score": 0.6323295373206566],
            ],
            "usage": [
                "prompt_tokens": 2966,
                "completion_tokens": 0,
                "total_tokens": 2966,
            ]
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.together.xyz/v1/rerank")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = TogetherAIRerankingModel(
            modelId: .salesforceLlamaRankV1,
            config: .init(
                provider: "togetherai.reranking",
                baseURL: "https://api.together.xyz/v1",
                headers: { ["authorization": "Bearer test-api-key"] },
                fetch: fetch
            )
        )

        let result = try await model.doRerank(
            options: RerankingModelV3CallOptions(
                documents: .text(values: ["sunny day at the beach", "rainy day in the city"]),
                query: "rainy day",
                topN: 2,
                providerOptions: [
                    "togetherai": [
                        "rankFields": .array([.string("example")])
                    ]
                ]
            )
        )

        #expect(result.ranking.count == 2)
        #expect(result.ranking[0].index == 0)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        if let docs = json["documents"] as? [String] {
            #expect(docs == ["sunny day at the beach", "rainy day in the city"])
        } else {
            Issue.record("Expected text documents array")
        }
    }
}

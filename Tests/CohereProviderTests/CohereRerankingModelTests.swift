import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import CohereProvider

@Suite("CohereRerankingModel")
struct CohereRerankingModelTests {
    private func makeModel() -> (CohereRerankingModel, RequestRecorder, ResponseBox) {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.rerankURL,
                statusCode: 500,
                httpVersion: "HTTP/1.1",
                headerFields: [:]
            )!
        )
        let responseBox = ResponseBox(initial: placeholderResponse)

        let fetch: FetchFunction = { request in
            await recorder.record(request)
            return await responseBox.value()
        }

        let provider = createCohere(settings: .init(apiKey: "test-api-key", fetch: fetch))
        return (provider.reranking(modelId: .rerankEnglishV30), recorder, responseBox)
    }

    private func setFixtureResponse(_ responseBox: ResponseBox) async {
        await responseBox.setJSON(
            url: HTTPTestHelpers.rerankURL,
            body: [
                "id": "b44fe75b-e3d3-489a-b61e-1a1aede3ef72",
                "results": [
                    ["index": 1, "relevance_score": 0.10183054],
                    ["index": 0, "relevance_score": 0.03762639],
                ],
                "meta": [
                    "api_version": ["version": "2"],
                    "billed_units": ["search_units": 1],
                ],
            ]
        )
    }

    @Test("stringifies object documents and returns compatibility warning")
    func jsonDocumentsFlow() async throws {
        let (model, recorder, responseBox) = makeModel()
        await setFixtureResponse(responseBox)

        let result = try await model.doRerank(options: .init(
            documents: .object(values: [
                ["example": .string("sunny day at the beach")],
                ["example": .string("rainy day in the city")],
            ]),
            query: "rainy day",
            topN: 2,
            providerOptions: [
                "cohere": [
                    "maxTokensPerDoc": .number(1000),
                    "priority": .number(1),
                ],
            ]
        ))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)

        #expect(body["model"] as? String == "rerank-english-v3.0")
        #expect(body["query"] as? String == "rainy day")
        #expect((body["top_n"] as? NSNumber)?.intValue == 2)
        #expect((body["max_tokens_per_doc"] as? NSNumber)?.intValue == 1000)
        #expect((body["priority"] as? NSNumber)?.intValue == 1)
        #expect(body["documents"] as? [String] == [
            #"{"example":"sunny day at the beach"}"#,
            #"{"example":"rainy day in the city"}"#,
        ])

        let headers = lowercaseHeaders(request)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["content-type"] == "application/json")

        #expect(result.warnings == [
            .compatibility(feature: "object documents", details: "Object documents are converted to strings."),
        ])

        #expect(result.ranking == [
            .init(index: 1, relevanceScore: 0.10183054),
            .init(index: 0, relevanceScore: 0.03762639),
        ])

        #expect(result.providerMetadata == nil)
        #expect(result.response?.id == "b44fe75b-e3d3-489a-b61e-1a1aede3ef72")
        #expect(result.response?.headers?["content-type"] == "application/json")
        #expect(result.response?.body != nil)
    }

    @Test("sends text documents and returns ranking without warnings")
    func textDocumentsFlow() async throws {
        let (model, recorder, responseBox) = makeModel()
        await setFixtureResponse(responseBox)

        let result = try await model.doRerank(options: .init(
            documents: .text(values: [
                "sunny day at the beach",
                "rainy day in the city",
            ]),
            query: "rainy day",
            topN: 2,
            providerOptions: [
                "cohere": [
                    "maxTokensPerDoc": .number(1000),
                    "priority": .number(1),
                ],
            ]
        ))

        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)

        #expect(body["documents"] as? [String] == [
            "sunny day at the beach",
            "rainy day in the city",
        ])

        let headers = lowercaseHeaders(request)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["content-type"] == "application/json")

        #expect(result.warnings.isEmpty)
        #expect(result.ranking == [
            .init(index: 1, relevanceScore: 0.10183054),
            .init(index: 0, relevanceScore: 0.03762639),
        ])
        #expect(result.providerMetadata == nil)
        #expect(result.response?.id == "b44fe75b-e3d3-489a-b61e-1a1aede3ef72")
        #expect(result.response?.body != nil)
    }

    @Test("numeric reranking options retain fractions and large finite values")
    func numericOptions() async throws {
        let (model, recorder, responseBox) = makeModel()
        let payload: [String: Any] = ["results": [["index": 0, "relevance_score": 0.5]], "meta": NSNull()]
        await responseBox.setJSON(url: HTTPTestHelpers.rerankURL, body: payload)
        let result = try await model.doRerank(options: .init(
            documents: .text(values: ["document"]), query: "query",
            providerOptions: ["cohere": ["maxTokensPerDoc": .number(1000.5), "priority": .number(1e100)]]
        ))
        let request = try #require(await recorder.first())
        let body = try decodeJSONBody(request)
        #expect(body["max_tokens_per_doc"] as? Double == 1000.5)
        #expect(body["priority"] as? Double == 1e100)
        #expect(result.ranking == [.init(index: 0, relevanceScore: 0.5)])
    }

    @Test("explicit null reranking options are invalid arguments", arguments: ["maxTokensPerDoc", "priority"])
    func nullOptions(key: String) async throws {
        let (model, _, _) = makeModel()
        await #expect(throws: InvalidArgumentError.self) {
            try await model.doRerank(options: .init(documents: .text(values: ["document"]), query: "query", providerOptions: ["cohere": [key: .null]]))
        }
    }
}

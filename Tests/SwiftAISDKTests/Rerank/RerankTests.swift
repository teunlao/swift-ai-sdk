import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import AmazonBedrockProvider
@testable import CohereProvider
@testable import SwiftAISDK

@Suite("rerank")
struct RerankTests {
    @Test("returns empty result without calling the model")
    func returnsEmptyResultWithoutCallingModel() async throws {
        actor CallCounter {
            var count = 0
            func increment() { count += 1 }
            func current() -> Int { count }
        }

        let counter = CallCounter()
        let model = TestRerankingModel(provider: "test", modelId: "test-model") { _ in
            await counter.increment()
            return RerankingModelV3DoRerankResult(ranking: [])
        }

        let result = try await rerank(
            model: model,
            documents: [String](),
            query: "q"
        )

        #expect(result.originalDocuments.isEmpty)
        #expect(result.ranking.isEmpty)
        #expect(result.rerankedDocuments.isEmpty)
        #expect(result.response.modelId == "test-model")
        #expect(await counter.current() == 0)
    }

    @Test("maps ranking entries and response metadata")
    func mapsRankingAndResponse() async throws {
        let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

        let model = TestRerankingModel(provider: "test", modelId: "test-model") { options in
            guard case .text(let values) = options.documents else {
                Issue.record("Expected text documents")
                return RerankingModelV3DoRerankResult(ranking: [])
            }

            #expect(values == ["a", "b", "c"])
            #expect(options.query == "query")
            #expect(options.topN == 2)
            #expect(options.headers?["user-agent"]?.contains("ai/\(VERSION)") == true)

            return RerankingModelV3DoRerankResult(
                ranking: [
                    RerankingModelV3Ranking(index: 2, relevanceScore: 0.9),
                    RerankingModelV3Ranking(index: 0, relevanceScore: 0.5),
                ],
                providerMetadata: ["test": ["note": .string("ok")]],
                response: RerankingModelV3ResponseInfo(
                    id: "resp-id",
                    timestamp: fixedDate,
                    modelId: "override-model",
                    headers: ["x-test": "1"],
                    body: nil
                )
            )
        }

        let result = try await rerank(
            model: model,
            documents: ["a", "b", "c"],
            query: "query",
            topN: 2
        )

        #expect(result.rerankedDocuments == ["c", "a"])
        #expect(result.ranking.count == 2)
        #expect(result.ranking[0].originalIndex == 2)
        #expect(result.ranking[0].score == 0.9)
        #expect(result.ranking[0].document == "c")
        #expect(result.providerMetadata?["test"]?["note"] == .string("ok"))
        #expect(result.response.id == "resp-id")
        #expect(result.response.timestamp == fixedDate)
        #expect(result.response.modelId == "override-model")
        #expect(result.response.headers?["x-test"] == "1")
    }

    @Test("logs reranking warnings")
    func logsWarnings() async throws {
        setWarningsLoggingDisabledForTests(true)
        defer { setWarningsLoggingDisabledForTests(false) }

        final class WarningsCapture: @unchecked Sendable {
            private let lock = NSLock()
            private var warnings: [Warning] = []

            func set(_ warnings: [Warning]) {
                lock.lock()
                self.warnings = warnings
                lock.unlock()
            }

            func get() -> [Warning] {
                lock.lock()
                defer { lock.unlock() }
                return warnings
            }
        }

        let capture = WarningsCapture()
        logWarningsObserver = { warnings in capture.set(warnings) }
        defer { logWarningsObserver = nil }

        let model = TestRerankingModel(provider: "test", modelId: "test-model") { _ in
            RerankingModelV3DoRerankResult(
                ranking: [],
                warnings: [
                    .unsupported(feature: "object documents", details: "not supported")
                ]
            )
        }

        _ = try await rerank(
            model: model,
            documents: ["a"],
            query: "q"
        )

        #expect(capture.get() == [
            .rerankingModel(.unsupported(feature: "object documents", details: "not supported"))
        ])
    }
}

@Suite("CohereRerankingModel")
struct CohereRerankingModelTests {
    @Test("doRerank builds request and maps response (text documents)")
    func doRerankTextDocuments() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "id": "cohere-rerank-id",
            "results": [
                ["index": 1, "relevance_score": 0.8]
            ],
            "meta": [:],
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.cohere.com/v2/rerank")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "x-cohere": "ok"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = CohereRerankingModel(
            modelId: .rerankEnglishV30,
            config: .init(
                provider: "cohere.reranking",
                baseURL: "https://api.cohere.com/v2",
                headers: { ["authorization": "Bearer test"] },
                fetch: fetch
            )
        )

        let result = try await model.doRerank(
            options: RerankingModelV3CallOptions(
                documents: .text(values: ["a", "b", "c"]),
                query: "q",
                topN: 2,
                providerOptions: [
                    "cohere": [
                        "maxTokensPerDoc": .number(128),
                        "priority": .number(1),
                    ]
                ],
                headers: ["x-override": "1"]
            )
        )

        #expect(result.ranking == [
            RerankingModelV3Ranking(index: 1, relevanceScore: 0.8)
        ])
        #expect(result.warnings.isEmpty)
        #expect(result.response?.id == "cohere-rerank-id")
        #expect(result.response?.headers?["x-cohere"] == "ok")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://api.cohere.com/v2/rerank")
        #expect(json["model"] as? String == "rerank-english-v3.0")
        #expect(json["query"] as? String == "q")
        #expect(json["top_n"] as? Double == 2)
        #expect(json["max_tokens_per_doc"] as? Double == 128)
        #expect(json["priority"] as? Double == 1)
        if let docs = json["documents"] as? [String] {
            #expect(docs == ["a", "b", "c"])
        } else {
            Issue.record("Expected documents array")
        }
    }

    @Test("doRerank converts object documents to strings and emits compatibility warning")
    func doRerankObjectDocuments() async throws {
        let responseJSON: [String: Any] = [
            "id": NSNull(),
            "results": [
                ["index": 0, "relevance_score": 0.9]
            ],
            "meta": [:],
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://api.cohere.com/v2/rerank")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!

        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = CohereRerankingModel(
            modelId: .rerankV35,
            config: .init(
                provider: "cohere.reranking",
                baseURL: "https://api.cohere.com/v2",
                headers: { [:] },
                fetch: fetch
            )
        )

        let documents: [JSONObject] = [
            ["title": .string("hello"), "score": .number(1)]
        ]

        let result = try await model.doRerank(
            options: RerankingModelV3CallOptions(
                documents: .object(values: documents),
                query: "q"
            )
        )

        #expect(result.warnings == [
            .compatibility(feature: "object documents", details: "Object documents are converted to strings.")
        ])

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any],
              let docs = json["documents"] as? [String],
              let first = docs.first
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(first.contains("\"title\""))
        #expect(first.contains("\"hello\""))
    }
}

@Suite("BedrockRerankingModel")
struct BedrockRerankingModelTests {
    @Test("doRerank builds request and maps response")
    func doRerankBuildsRequest() async throws {
        actor RequestCapture {
            var request: URLRequest?
            func store(_ request: URLRequest) { self.request = request }
            func current() -> URLRequest? { request }
        }

        let capture = RequestCapture()

        let responseJSON: [String: Any] = [
            "results": [
                ["index": 0, "relevanceScore": 0.7]
            ],
            "nextToken": "next",
        ]

        let responseData = try JSONSerialization.data(withJSONObject: responseJSON)
        let httpResponse = HTTPURLResponse(
            url: URL(string: "https://bedrock-runtime.us-east-1.amazonaws.com/rerank")!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json", "x-bedrock": "ok"]
        )!

        let fetch: FetchFunction = { request in
            await capture.store(request)
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = BedrockRerankingModel(
            modelId: .amazonRerankV1_0,
            config: .init(
                baseURL: { "https://bedrock-runtime.us-east-1.amazonaws.com" },
                region: "us-east-1",
                headers: { [:] },
                fetch: fetch
            )
        )

        let result = try await model.doRerank(
            options: RerankingModelV3CallOptions(
                documents: .text(values: ["a", "b"]),
                query: "q",
                topN: 1,
                providerOptions: [
                    "bedrock": [
                        "nextToken": .string("token"),
                        "additionalModelRequestFields": .object(["foo": .string("bar")]),
                    ]
                ]
            )
        )

        #expect(result.ranking == [
            RerankingModelV3Ranking(index: 0, relevanceScore: 0.7)
        ])
        #expect(result.response?.headers?["x-bedrock"] == "ok")

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "https://bedrock-runtime.us-east-1.amazonaws.com/rerank")
        #expect(json["nextToken"] as? String == "token")

        if let queries = json["queries"] as? [[String: Any]],
           let first = queries.first {
            #expect(first["type"] as? String == "TEXT")
            if let textQuery = first["textQuery"] as? [String: Any] {
                #expect(textQuery["text"] as? String == "q")
            } else {
                Issue.record("Expected textQuery object")
            }
        } else {
            Issue.record("Expected queries array")
        }

        if let config = json["rerankingConfiguration"] as? [String: Any],
           let type = config["type"] as? String {
            #expect(type == "BEDROCK_RERANKING_MODEL")
            if let bedrockConfig = config["bedrockRerankingConfiguration"] as? [String: Any],
               let modelConfig = bedrockConfig["modelConfiguration"] as? [String: Any] {
                #expect(modelConfig["modelArn"] as? String == "arn:aws:bedrock:us-east-1::foundation-model/amazon.rerank-v1:0")
                if let additional = modelConfig["additionalModelRequestFields"] as? [String: Any] {
                    #expect(additional["foo"] as? String == "bar")
                } else {
                    Issue.record("Expected additionalModelRequestFields")
                }
            } else {
                Issue.record("Expected bedrockRerankingConfiguration.modelConfiguration")
            }
        } else {
            Issue.record("Expected rerankingConfiguration object")
        }

        if let sources = json["sources"] as? [[String: Any]],
           let first = sources.first,
           let inline = first["inlineDocumentSource"] as? [String: Any] {
            #expect(first["type"] as? String == "INLINE")
            #expect(inline["type"] as? String == "TEXT")
            if let textDoc = inline["textDocument"] as? [String: Any] {
                #expect(textDoc["text"] as? String == "a")
            } else {
                Issue.record("Expected textDocument object")
            }
        } else {
            Issue.record("Expected sources array")
        }
    }
}

// MARK: - Test Helpers

private final class TestRerankingModel: RerankingModelV3, @unchecked Sendable {
    let providerValue: String
    let modelIdentifier: String
    let handler: @Sendable (RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult

    init(
        provider: String,
        modelId: String,
        handler: @escaping @Sendable (RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult
    ) {
        self.providerValue = provider
        self.modelIdentifier = modelId
        self.handler = handler
    }

    var provider: String { providerValue }
    var modelId: String { modelIdentifier }

    func doRerank(options: RerankingModelV3CallOptions) async throws -> RerankingModelV3DoRerankResult {
        try await handler(options)
    }
}

import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import AmazonBedrockProvider

@Suite("BedrockEmbeddingModel")
struct BedrockEmbeddingModelTests {
    actor RequestCapture {
        private(set) var request: URLRequest?
        func store(_ request: URLRequest) { self.request = request }
        func current() -> URLRequest? { request }
    }

    private let mockEmbedding: [Double] = [-0.09, 0.05, -0.02, 0.01, 0.04]
    private let testValue = "sunny day at the beach"
    private let baseURL = "https://bedrock-runtime.us-east-1.amazonaws.com"

    private func normalizedHeaders(_ request: URLRequest) -> [String: String] {
        (request.allHTTPHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            let key = pair.key.lowercased()
            if key == "user-agent" { return }
            result[key] = pair.value
        }
    }

    private func httpResponse(
        for request: URLRequest,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) throws -> HTTPURLResponse {
        let url = try #require(request.url)
        return try #require(HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    private func makeModel(
        modelId: BedrockEmbeddingModelId,
        headers: [String: String?] = [:],
        fetch: @escaping FetchFunction
    ) -> BedrockEmbeddingModel {
        BedrockEmbeddingModel(
            modelId: modelId,
            config: BedrockEmbeddingConfig(
                baseURL: { baseURL },
                headers: { headers },
                fetch: fetch
            )
        )
    }

    @Test("doEmbed handles Titan embedding models and maps request body")
    func doEmbedTitanEmbeddingsAndRequestBody() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embedding": mockEmbedding,
            "inputTextTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(
            modelId: .amazonTitanEmbedTextV2,
            headers: [
                "config-header": "config-value",
                "shared-header": "config-shared",
            ],
            fetch: fetch
        )

        let result = try await model.doEmbed(options: .init(values: [testValue]))
        #expect(result.embeddings == [mockEmbedding])

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "\(baseURL)/model/amazon.titan-embed-text-v2%3A0/invoke")
        #expect(json["inputText"] as? String == testValue)
        #expect(json["dimensions"] == nil)
        #expect(json["normalize"] == nil)
    }

    @Test("doEmbed extracts usage for Titan embedding models")
    func doEmbedTitanUsage() async throws {
        let responseBody: [String: Any] = [
            "embedding": mockEmbedding,
            "inputTextTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: .amazonTitanEmbedTextV2, fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: [testValue]))

        #expect(result.usage?.tokens == 8)
    }

    @Test("doEmbed supports Cohere v3 embedding models")
    func doEmbedCohereV3() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [mockEmbedding],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: .cohereEmbedEnglishV3, fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: [testValue]))

        #expect(result.embeddings == [mockEmbedding])
        // Upstream returns NaN for Cohere token usage. Swift uses nil to represent "unknown".
        #expect(result.usage == nil)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "\(baseURL)/model/cohere.embed-english-v3/invoke")
        #expect(json["input_type"] as? String == "search_query")
        #expect(json["texts"] as? [String] == [testValue])
        #expect(json["truncate"] == nil)
        #expect(json["output_dimension"] == nil)
    }

    @Test("doEmbed supports Cohere v4 embedding models")
    func doEmbedCohereV4() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [
                "float": [mockEmbedding]
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: "cohere.embed-v4:0", fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: [testValue]))

        #expect(result.embeddings == [mockEmbedding])
        // Upstream returns NaN for Cohere token usage. Swift uses nil to represent "unknown".
        #expect(result.usage == nil)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "\(baseURL)/model/cohere.embed-v4%3A0/invoke")
        #expect(json["input_type"] as? String == "search_query")
        #expect(json["texts"] as? [String] == [testValue])
        #expect(json["truncate"] == nil)
        #expect(json["output_dimension"] == nil)
    }

    @Test("doEmbed passes outputDimension for Cohere v4 embedding models")
    func doEmbedCohereV4OutputDimension() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [
                "float": [mockEmbedding]
            ],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: "cohere.embed-v4:0", fetch: fetch)
        let result = try await model.doEmbed(options: .init(
            values: [testValue],
            providerOptions: [
                "bedrock": ["outputDimension": .number(256)]
            ]
        ))

        #expect(result.embeddings == [mockEmbedding])

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["output_dimension"] as? Double == 256)
        #expect(json["truncate"] == nil)
    }

    @Test("doEmbed combines headers from model config, call overrides, and fetch injection")
    func doEmbedCombinesHeaders() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embedding": mockEmbedding,
            "inputTextTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            var request = request
            request.setValue("signed-value", forHTTPHeaderField: "signed-header")
            request.setValue("AWS4-HMAC-SHA256...", forHTTPHeaderField: "authorization")

            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(
            modelId: .amazonTitanEmbedTextV2,
            headers: [
                "model-header": "model-value",
                "shared-header": "model-shared",
            ],
            fetch: fetch
        )

        _ = try await model.doEmbed(options: .init(
            values: [testValue],
            headers: [
                "options-header": "options-value",
                "shared-header": "options-shared",
            ]
        ))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(request)
        #expect(headers["options-header"] == "options-value")
        #expect(headers["model-header"] == "model-value")
        #expect(headers["signed-header"] == "signed-value")
        #expect(headers["authorization"] == "AWS4-HMAC-SHA256...")
        #expect(headers["shared-header"] == "options-shared")
    }

    @Test("doEmbed works with partial headers")
    func doEmbedPartialHeaders() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embedding": mockEmbedding,
            "inputTextTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            var request = request
            request.setValue("signed-value", forHTTPHeaderField: "signed-header")
            request.setValue("AWS4-HMAC-SHA256...", forHTTPHeaderField: "authorization")

            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(
            modelId: .amazonTitanEmbedTextV2,
            headers: [
                "model-header": "model-value",
            ],
            fetch: fetch
        )

        _ = try await model.doEmbed(options: .init(values: [testValue]))

        guard let request = await capture.current() else {
            Issue.record("Missing request capture")
            return
        }

        let headers = normalizedHeaders(request)
        #expect(headers["model-header"] == "model-value")
        #expect(headers["signed-header"] == "signed-value")
        #expect(headers["authorization"] == "AWS4-HMAC-SHA256...")
    }

    @Test("doEmbed supports Nova embeddings and sends SINGLE_EMBEDDING payload")
    func doEmbedNovaPayloadDefault() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [
                [
                    "embeddingType": "TEXT",
                    "embedding": mockEmbedding,
                ],
            ],
            "inputTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: "amazon.nova-2-multimodal-embeddings-v1:0", fetch: fetch)
        let result = try await model.doEmbed(options: .init(values: [testValue]))

        #expect(result.embeddings == [mockEmbedding])
        #expect(result.usage?.tokens == 8)

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(request.url?.absoluteString == "\(baseURL)/model/amazon.nova-2-multimodal-embeddings-v1%3A0/invoke")
        #expect(json["taskType"] as? String == "SINGLE_EMBEDDING")

        guard let params = json["singleEmbeddingParams"] as? [String: Any],
              let text = params["text"] as? [String: Any]
        else {
            Issue.record("Expected singleEmbeddingParams.text")
            return
        }

        #expect(params["embeddingPurpose"] as? String == "GENERIC_INDEX")
        #expect(params["embeddingDimension"] as? Double == 1024)
        #expect(text["truncationMode"] as? String == "END")
        #expect(text["value"] as? String == testValue)
    }

    @Test("doEmbed passes embeddingDimension for Nova embeddings")
    func doEmbedNovaEmbeddingDimension() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [
                [
                    "embeddingType": "TEXT",
                    "embedding": mockEmbedding,
                ],
            ],
            "inputTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: "amazon.nova-2-multimodal-embeddings-v1:0", fetch: fetch)
        _ = try await model.doEmbed(options: .init(
            values: [testValue],
            providerOptions: [
                "bedrock": ["embeddingDimension": .number(256)]
            ]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        guard let params = json["singleEmbeddingParams"] as? [String: Any] else {
            Issue.record("Expected singleEmbeddingParams")
            return
        }

        #expect(params["embeddingDimension"] as? Double == 256)
    }

    @Test("doEmbed maps Bedrock provider options for Cohere inputType/truncate")
    func doEmbedCohereInputTypeAndTruncate() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [mockEmbedding],
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: .cohereEmbedEnglishV3, fetch: fetch)
        _ = try await model.doEmbed(options: .init(
            values: [testValue],
            providerOptions: [
                "bedrock": [
                    "inputType": .string("classification"),
                    "truncate": .string("START"),
                ]
            ]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        #expect(json["input_type"] as? String == "classification")
        #expect(json["truncate"] as? String == "START")
    }

    @Test("doEmbed maps Bedrock provider options for Nova embeddingPurpose/truncate")
    func doEmbedNovaEmbeddingPurposeAndTruncate() async throws {
        let capture = RequestCapture()

        let responseBody: [String: Any] = [
            "embeddings": [
                [
                    "embeddingType": "TEXT",
                    "embedding": mockEmbedding,
                ],
            ],
            "inputTokenCount": 8,
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            await capture.store(request)
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: "amazon.nova-2-multimodal-embeddings-v1:0", fetch: fetch)
        _ = try await model.doEmbed(options: .init(
            values: [testValue],
            providerOptions: [
                "bedrock": [
                    "embeddingPurpose": .string("TEXT_RETRIEVAL"),
                    "truncate": .string("START"),
                ]
            ]
        ))

        guard let request = await capture.current(),
              let body = request.httpBody,
              let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        else {
            Issue.record("Missing request capture")
            return
        }

        guard let params = json["singleEmbeddingParams"] as? [String: Any],
              let text = params["text"] as? [String: Any]
        else {
            Issue.record("Expected singleEmbeddingParams.text")
            return
        }

        #expect(params["embeddingPurpose"] as? String == "TEXT_RETRIEVAL")
        #expect(text["truncationMode"] as? String == "START")
    }

    @Test("doEmbed throws TypeValidationError for unknown response shapes")
    func doEmbedUnexpectedResponseShapeThrows() async throws {
        let responseBody: [String: Any] = [
            "unexpected": "shape",
        ]
        let responseData = try JSONSerialization.data(withJSONObject: responseBody, options: [.sortedKeys])

        let fetch: FetchFunction = { request in
            let httpResponse = try httpResponse(for: request, headers: ["Content-Type": "application/json"])
            return FetchResponse(body: .data(responseData), urlResponse: httpResponse)
        }

        let model = makeModel(modelId: .amazonTitanEmbedTextV2, fetch: fetch)

        do {
            _ = try await model.doEmbed(options: .init(values: [testValue]))
            Issue.record("Expected error")
        } catch {
            #expect(TypeValidationError.isInstance(error))
        }
    }
}


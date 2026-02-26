import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import CohereProvider

@Suite("CohereEmbeddingModel")
struct CohereEmbeddingModelTests {
    private let testValues = ["sunny day at the beach", "rainy day in the city"]

    private func makeModel(headers: [String: String]? = nil) -> (CohereEmbeddingModel, RequestRecorder, ResponseBox) {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.embeddingURL,
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

        let provider = createCohere(settings: .init(
            apiKey: "test-api-key",
            headers: headers,
            fetch: fetch
        ))

        return (provider.embedding(modelId: .embedEnglishV3), recorder, responseBox)
    }

    @Test("doEmbed extracts embeddings")
    func extractsEmbeddings() async throws {
        let (model, _, responseBox) = makeModel()

        let embeddings: [[Double]] = [
            [0.03302002, 0.020904541, -0.019744873, -0.0625, 0.04437256],
            [-0.04660034, 0.00037765503, -0.061157227, -0.08239746, -0.010360718],
        ]

        await responseBox.setJSON(url: HTTPTestHelpers.embeddingURL, body: [
            "id": "f5aa3e7b-f011-4c5c-a825-f94669f760e5",
            "texts": testValues,
            "embeddings": ["float": embeddings],
            "meta": [
                "api_version": ["version": "2"],
                "billed_units": ["input_tokens": 10],
            ],
            "response_type": "embeddings_by_type",
        ])

        let result = try await model.doEmbed(options: .init(values: testValues))
        #expect(result.embeddings == embeddings)
    }

    @Test("doEmbed exposes raw response headers/body")
    func exposesRawResponse() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "embeddings": ["float": [[0.0]]],
                "meta": ["billed_units": ["input_tokens": 1]],
            ],
            headers: ["Test-Header": "test-value"]
        )

        let result = try await model.doEmbed(options: .init(values: testValues))
        let headers = result.response?.headers ?? [:]
        #expect(headers["test-header"] == "test-value")
        #expect(headers["content-type"] == "application/json")
        #expect(result.response?.body != nil)
    }

    @Test("doEmbed extracts usage")
    func extractsUsage() async throws {
        let (model, _, responseBox) = makeModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "embeddings": ["float": [[0.0]]],
                "meta": ["billed_units": ["input_tokens": 10]],
            ]
        )

        let result = try await model.doEmbed(options: .init(values: testValues))
        #expect(result.usage?.tokens == 10)
    }

    @Test("doEmbed passes model and values")
    func requestPayload() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "embeddings": ["float": [[0.0]]],
                "meta": ["billed_units": ["input_tokens": 1]],
            ]
        )

        _ = try await model.doEmbed(options: .init(values: testValues))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect(body["model"] as? String == "embed-english-v3.0")
        #expect(body["embedding_types"] as? [String] == ["float"])
        #expect(body["input_type"] as? String == "search_query")
        #expect(body["texts"] as? [String] == testValues)
    }

    @Test("doEmbed passes the inputType setting")
    func inputTypeSetting() async throws {
        let (model, recorder, responseBox) = makeModel()
        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "embeddings": ["float": [[0.0]]],
                "meta": ["billed_units": ["input_tokens": 1]],
            ]
        )

        _ = try await model.doEmbed(options: .init(
            values: testValues,
            providerOptions: ["cohere": ["inputType": .string("search_document")]]
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect(body["input_type"] as? String == "search_document")
    }

    @Test("doEmbed passes the outputDimension setting")
    func outputDimensionSetting() async throws {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.embeddingURL,
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
        let model = provider.embedding(modelId: CohereEmbeddingModelId(rawValue: "embed-v4.0"))

        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "embeddings": ["float": [[0.0]]],
                "meta": ["billed_units": ["input_tokens": 1]],
            ]
        )

        _ = try await model.doEmbed(options: .init(
            values: testValues,
            providerOptions: ["cohere": ["outputDimension": .number(256)]]
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let body = try decodeJSONBody(request)
        #expect((body["output_dimension"] as? NSNumber)?.intValue == 256)
    }

    @Test("doEmbed merges headers")
    func requestHeaders() async throws {
        let recorder = RequestRecorder()
        let placeholderResponse = FetchResponse(
            body: .data(Data()),
            urlResponse: HTTPURLResponse(
                url: HTTPTestHelpers.embeddingURL,
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

        let provider = createCohere(settings: .init(
            apiKey: "test-api-key",
            headers: ["Custom-Provider-Header": "provider-header-value"],
            fetch: fetch
        ))

        await responseBox.setJSON(
            url: HTTPTestHelpers.embeddingURL,
            body: [
                "embeddings": ["float": [[0.0]]],
                "meta": ["billed_units": ["input_tokens": 1]],
            ]
        )

        _ = try await provider.embedding(modelId: .embedEnglishV3).doEmbed(options: .init(
            values: testValues,
            headers: ["Custom-Request-Header": "request-header-value"]
        ))

        guard let request = await recorder.first() else {
            Issue.record("Missing request")
            return
        }

        let headers = lowercaseHeaders(request)
        #expect(headers["authorization"] == "Bearer test-api-key")
        #expect(headers["content-type"] == "application/json")
        #expect(headers["custom-provider-header"] == "provider-header-value")
        #expect(headers["custom-request-header"] == "request-header-value")

        let userAgent = request.value(forHTTPHeaderField: "User-Agent") ?? ""
        #expect(userAgent.contains("ai-sdk/cohere/\(COHERE_VERSION)"))
    }
}


import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

/// Tests for the `embed` API.
///
/// Port of `@ai-sdk/ai/src/embed/embed.test.ts`.
@Suite("Embed Tests")
struct EmbedTests {
    private let dummyEmbedding: Embedding = [0.1, 0.2, 0.3]
    private let testValue = "sunny day at the beach"

    @Test("result.embedding should match model output")
    func resultEmbeddingMatches() async throws {
        let model = TestEmbeddingModelV3<String> { options in
            #expect(options.values == [testValue])
            return EmbeddingModelV3DoEmbedResult(embeddings: [dummyEmbedding])
        }

        let result = try await embed(
            model: .v3(model),
            value: testValue
        )

        #expect(result.embedding == dummyEmbedding)
    }

    @Test("result.response should include provider response")
    func resultIncludesResponse() async throws {
        let response = EmbeddingModelV3ResponseInfo(
            headers: ["foo": "bar"],
            body: ["foo": "bar"]
        )

        let model = TestEmbeddingModelV3<String> { _ in
            EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbedding],
                response: response
            )
        }

        let result = try await embed(
            model: .v3(model),
            value: testValue
        )

        let body = result.response?.body as? [String: String]
        #expect(body == ["foo": "bar"])
        #expect(result.response?.headers == ["foo": "bar"])
    }

    @Test("result.value echoes input")
    func resultIncludesValue() async throws {
        let model = TestEmbeddingModelV3<String> { _ in
            EmbeddingModelV3DoEmbedResult(embeddings: [dummyEmbedding])
        }

        let result = try await embed(
            model: .v3(model),
            value: testValue
        )

        #expect(result.value == testValue)
    }

    @Test("result.usage reflects provider usage")
    func resultIncludesUsage() async throws {
        let model = TestEmbeddingModelV3<String> { _ in
            EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbedding],
                usage: EmbeddingModelV3Usage(tokens: 10)
            )
        }

        let result = try await embed(
            model: .v3(model),
            value: testValue
        )

        #expect(result.usage == EmbeddingModelUsage(tokens: 10))
    }

    @Test("result.providerMetadata mirrors provider output")
    func resultIncludesProviderMetadata() async throws {
        let providerMetadata: ProviderMetadata = [
            "gateway": [
                "routing": .object(["resolvedProvider": .string("test-provider")])
            ]
        ]

        let model = TestEmbeddingModelV3<String> { _ in
            EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbedding],
                providerMetadata: providerMetadata
            )
        }

        let result = try await embed(
            model: .v3(model),
            value: testValue
        )

        #expect(result.providerMetadata == providerMetadata)
    }

    @Test("headers option augments provider headers")
    func headersOptionIsForwarded() async throws {
        let capturedHeaders = HeadersCapture()

        let model = TestEmbeddingModelV3<String> { options in
            await capturedHeaders.set(options.headers)
            return EmbeddingModelV3DoEmbedResult(embeddings: [dummyEmbedding])
        }

        let result = try await embed(
            model: .v3(model),
            value: testValue,
            headers: ["custom-request-header": "request-header-value"]
        )

        #expect(result.embedding == dummyEmbedding)
        let headers: [String: String]? = await capturedHeaders.get()
        let expected: [String: String] = [
            "custom-request-header": "request-header-value",
            "user-agent": "ai/\(VERSION)",
        ]
        #expect(headers == expected)
    }

    @Test("providerOptions are passed through untouched")
    func providerOptionsForwarded() async throws {
        let expectedOptions: ProviderOptions = [
            "aProvider": ["someKey": .string("someValue")]
        ]

        let model = TestEmbeddingModelV3<String> { options in
            #expect(options.providerOptions == expectedOptions)
            return EmbeddingModelV3DoEmbedResult(embeddings: [[1, 2, 3]])
        }

        let result = try await embed(
            model: .v3(model),
            value: "test-input",
            providerOptions: expectedOptions
        )

        #expect(result.embedding == [1, 2, 3])
    }

    @Test("telemetry disabled does not record spans")
    func telemetryDisabledRecordsNoSpans() async throws {
        let tracer = MockTracer()

        _ =
            try await embed(
                model: .v3(
                    TestEmbeddingModelV3<String> { _ in
                        EmbeddingModelV3DoEmbedResult(embeddings: [dummyEmbedding])
                    }
                ),
                value: testValue,
                experimentalTelemetry: TelemetrySettings(tracer: tracer)
            ) as DefaultEmbedResult<String>

        #expect(tracer.spanRecords.isEmpty)
    }

    @Test("telemetry enabled records expected spans")
    func telemetryEnabledRecordsSpans() async throws {
        let tracer = MockTracer()

        _ =
            try await embed(
                model: .v3(
                    TestEmbeddingModelV3<String> { _ in
                        EmbeddingModelV3DoEmbedResult(
                            embeddings: [dummyEmbedding],
                            usage: EmbeddingModelV3Usage(tokens: 10)
                        )
                    }
                ),
                value: testValue,
                experimentalTelemetry: TelemetrySettings(
                    isEnabled: true,
                    functionId: "test-function-id",
                    metadata: [
                        "test1": .string("value1"),
                        "test2": .bool(false),
                    ],
                    tracer: tracer
                )
            ) as DefaultEmbedResult<String>

        let spans = tracer.spanRecords
        #expect(spans.count == 2)

        if spans.count >= 2 {
            let outer = spans[0]
            #expect(outer.name == "ai.embed")
            #expect(outer.attributes["ai.model.id"] == .string("test-model"))
            #expect(outer.attributes["ai.model.provider"] == .string("test-provider"))
            #expect(
                outer.attributes["ai.value"] == .string(embedTelemetryJSONString(from: testValue))
            )
            #expect(outer.attributes["ai.telemetry.functionId"] == .string("test-function-id"))
            #expect(outer.attributes["ai.telemetry.metadata.test1"] == .string("value1"))
            #expect(outer.attributes["ai.telemetry.metadata.test2"] == .bool(false))
            #expect(outer.attributes["ai.usage.tokens"] == .int(10))

            let inner = spans[1]
            #expect(inner.name == "ai.embed.doEmbed")
            #expect(
                inner.attributes["ai.values"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(from: [testValue as Any])
                    )
            )
            #expect(
                inner.attributes["ai.embeddings"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(from: [dummyEmbedding as Any])
                    )
            )
            #expect(inner.attributes["ai.usage.tokens"] == .int(10))
        }
    }

    @Test("telemetry respects recordInputs and recordOutputs flags")
    func telemetryRespectsRecordFlags() async throws {
        let tracer = MockTracer()

        _ =
            try await embed(
                model: .v3(
                    TestEmbeddingModelV3<String> { _ in
                        EmbeddingModelV3DoEmbedResult(
                            embeddings: [dummyEmbedding],
                            usage: EmbeddingModelV3Usage(tokens: 10)
                        )
                    }
                ),
                value: testValue,
                experimentalTelemetry: TelemetrySettings(
                    isEnabled: true,
                    recordInputs: false,
                    recordOutputs: false,
                    tracer: tracer
                )
            ) as DefaultEmbedResult<String>

        let spans = tracer.spanRecords
        #expect(spans.count == 2)

        if spans.count >= 2 {
            let outer = spans[0]
            #expect(outer.attributes["ai.value"] == nil)
            #expect(outer.attributes["ai.embedding"] == nil)

            let inner = spans[1]
            #expect(inner.attributes["ai.values"] == nil)
            #expect(inner.attributes["ai.embeddings"] == nil)
        }
    }
}

// MARK: - Helpers

private actor HeadersCapture {
    private var headers: [String: String]?

    func set(_ headers: [String: String]?) {
        self.headers = headers
    }

    func get() -> [String: String]? {
        headers
    }
}

extension TestEmbeddingModelV3 where Value == String {
    fileprivate convenience init(
        supportsParallelCalls: Bool = true,
        maxEmbeddingsPerCall: Int? = nil,
        doEmbed: @escaping @Sendable (EmbeddingModelV3DoEmbedOptions<String>) async throws ->
            EmbeddingModelV3DoEmbedResult
    ) {
        self.init(
            provider: "test-provider",
            modelId: "test-model",
            maxEmbeddingsPerCall: maxEmbeddingsPerCall,
            supportsParallelCalls: supportsParallelCalls,
            doEmbed: doEmbed
        )
    }
}

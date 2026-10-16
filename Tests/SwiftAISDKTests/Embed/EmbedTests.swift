import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing
import GatewayProvider

@testable import SwiftAISDK

/// Tests for the `embed` API.
///
/// Port of `@ai-sdk/ai/src/embed/embed.test.ts`.
@Suite("Embed Tests")
struct EmbedTests {
    private let dummyEmbedding: Embedding = [0.1, 0.2, 0.3]
    private let testValue = "sunny day at the beach"

    @Test("dimensions and runtime callbacks describe the same embedding operation")
    func dimensionsAndCallbacks() async throws {
        actor Events {
            var phases: [String] = []
            func append(_ phase: String) { phases.append(phase) }
        }
        let events = Events()
        let model = TestEmbeddingModelV4 { options in
            await events.append("model")
            return EmbeddingModelV4Result(embeddings: [Array(repeating: 1, count: options.dimensions ?? 0)])
        }
        let result = try await embed(
            model: model, value: "hello", dimensions: 2,
            runtimeContext: ["requestId": "request-1"],
            onStart: { event in
                #expect(event.runtimeContext["requestId"] == .string("request-1"))
                #expect(event.dimensions == 2)
                await events.append("start")
                throw CancellationError()
            },
            onEnd: { event in
                #expect(event.embedding == [1, 1])
                #expect(event.usage.tokens.isNaN)
                await events.append("end")
                throw CancellationError()
            }
        )
        #expect(result.embedding == [1, 1])
        #expect(result.usage.tokens.isNaN)
        let usageJSON = try JSONEncoder().encode(result.usage)
        #expect(try JSONDecoder().decode([String: JSONValue].self, from: usageJSON)["tokens"] == .null)
        #expect(try JSONDecoder().decode(EmbeddingModelUsage.self, from: usageJSON).tokens.isNaN)
        #expect(await events.phases == ["start", "model", "end"])
    }

    @Test("retryable gateway failures retry to a generated embedding")
    func retriesGatewayFailure() async throws {
        actor Attempts {
            var count = 0
            func next() -> Int { count += 1; return count }
        }
        let attempts = Attempts()
        let model = TestEmbeddingModelV4 { _ in
            if await attempts.next() == 1 {
                throw GatewayRateLimitError(cause: APICallError(
                    message: "rate limit", url: "https://example.com/embed", requestBodyValues: nil,
                    statusCode: 429, responseHeaders: ["retry-after-ms": "0"]
                ))
            }
            return EmbeddingModelV4Result(embeddings: [[1]])
        }
        let result = try await embed(model: model, value: "hello", maxRetries: 1)
        #expect(result.embedding == [1])
    }

    @Test("unsupported model specifications are rejected before generation")
    func rejectsUnsupportedSpecification() async throws {
        let model = TestEmbeddingModelV4(specificationVersion: "v1") { _ in
            EmbeddingModelV4Result(embeddings: [[1]])
        }
        await #expect(throws: UnsupportedModelVersionError.self) {
            _ = try await embed(model: model, value: "hello")
        }
    }

    @Test("missing embedding is an invalid provider response")
    func missingEmbedding() async throws {
        let model = TestEmbeddingModelV4 { _ in EmbeddingModelV4Result(embeddings: []) }
        await #expect(throws: InvalidResponseDataError.self) {
            _ = try await embed(model: model, value: "hello")
        }
    }

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

    @Test("direct V4 model uses V4 call options and preserves warnings")
    func directV4ModelUsesV4RuntimeSurface() async throws {
        let capturedOptions = V4EmbeddingOptionsCapture()
        let expectedOptions: ProviderOptions = [
            "aProvider": ["someKey": .string("someValue")]
        ]
        let expectedWarning = SharedV4Warning.deprecated(
            setting: "dimensions",
            message: "Use provider-native dimensions instead."
        )
        let providerMetadata: ProviderMetadata = [
            "gateway": ["routing": .string("direct-v4")]
        ]

        let model = TestEmbeddingModelV4 { options in
            await capturedOptions.set(options)
            return EmbeddingModelV4Result(
                embeddings: [dummyEmbedding],
                usage: EmbeddingModelV4Usage(tokens: 7),
                providerMetadata: providerMetadata,
                response: EmbeddingModelV4ResponseInfo(
                    headers: ["x-provider": "v4"],
                    body: ["ok": true]
                ),
                warnings: [expectedWarning]
            )
        }

        let result = try await embed(
            model: .v4(model),
            value: testValue,
            providerOptions: expectedOptions,
            headers: ["custom-request-header": "request-header-value"]
        )

        let options = try #require(await capturedOptions.get())
        #expect(options.values == [testValue])
        #expect(options.providerOptions == expectedOptions)
        #expect(
            options.headers == [
                "custom-request-header": "request-header-value",
                "user-agent": "ai/\(VERSION)",
            ])
        #expect(result.embedding == dummyEmbedding)
        #expect(result.usage == EmbeddingModelUsage(tokens: 7))
        #expect(result.warnings == [expectedWarning])
        #expect(result.providerMetadata == providerMetadata)
        #expect(result.response?.headers == ["x-provider": "v4"])
        #expect(result.response?.body as? [String: Bool] == ["ok": true])
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
                telemetry: TelemetryOptions(isEnabled: false, integrations: [LegacyOpenTelemetry(tracer: tracer)])
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
                telemetry: TelemetryOptions(
                    functionId: "test-function-id",
                    includeRuntimeContext: ["tenant": true],
                    integrations: [LegacyOpenTelemetry(tracer: tracer)]
                ),
                runtimeContext: ["tenant": .string("acme"), "secret": .string("hidden")]
            ) as DefaultEmbedResult<String>

        let spans = tracer.spanRecords
        #expect(spans.map(\.name) == ["ai.embed", "ai.embed.doEmbed"])

        if spans.count >= 2 {
            let outer = spans[0]
            #expect(outer.attributes["ai.model.id"] == .string("test-model"))
            #expect(outer.attributes["ai.model.provider"] == .string("test-provider"))
            #expect(outer.attributes["ai.value"] == .string("\"sunny day at the beach\""))
            #expect(outer.attributes["ai.embedding"] == .string("[0.1,0.2,0.3]"))
            #expect(outer.attributes["ai.telemetry.functionId"] == .string("test-function-id"))
            #expect(outer.attributes["ai.settings.context.tenant"] == .string("acme"))
            #expect(outer.attributes["ai.settings.context.secret"] == nil)
            #expect(outer.attributes["ai.usage.tokens"] == .int(10))

            let inner = spans[1]
            #expect(inner.attributes["ai.values"] == .stringArray(["\"sunny day at the beach\""]))
            #expect(inner.attributes["ai.embeddings"] == .stringArray(["[0.1,0.2,0.3]"]))
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
                telemetry: TelemetryOptions(
                    recordInputs: false,
                    recordOutputs: false,
                    integrations: [LegacyOpenTelemetry(tracer: tracer)]
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
        return headers
    }
}

private actor V4EmbeddingOptionsCapture {
    private var options: EmbeddingModelV4CallOptions?

    func set(_ options: EmbeddingModelV4CallOptions) {
        self.options = options
    }

    func get() -> EmbeddingModelV4CallOptions? {
        options
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

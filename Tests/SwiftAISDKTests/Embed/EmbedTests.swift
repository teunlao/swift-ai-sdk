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
                #expect(event.usage.tokens == 0)
                await events.append("end")
                throw CancellationError()
            }
        )
        #expect(result.embedding == [1, 1])
        #expect(result.usage.tokens == 0)
        #expect(await events.phases == ["start", "model", "end"])
    }

    @Test("stored embedding usage that is fractional or beyond Int decodes as unreported")
    func decodesUnrepresentableUsageAsUnreported() throws {
        func decode(_ json: String) throws -> Int {
            try JSONDecoder().decode(EmbeddingModelUsage.self, from: Data(json.utf8)).tokens
        }
        #expect(try decode(#"{"tokens":12}"#) == 12)
        #expect(try decode(#"{"tokens":1.5}"#) == 0)
        #expect(try decode(#"{"tokens":1e30}"#) == 0)
        #expect(try decode(#"{"tokens":null}"#) == 0)
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
        let model = TestEmbeddingModelV4 { options in
            #expect(options.values == [testValue])
            return EmbeddingModelV4Result(embeddings: [dummyEmbedding])
        }

        let result = try await embed(
            model: model,
            value: testValue
        )

        #expect(result.embedding == dummyEmbedding)
    }

    @Test("result.response should include provider response")
    func resultIncludesResponse() async throws {
        let response = EmbeddingModelV4ResponseInfo(
            headers: ["foo": "bar"],
            body: ["foo": "bar"]
        )

        let model = TestEmbeddingModelV4 { _ in
            EmbeddingModelV4Result(
                embeddings: [dummyEmbedding],
                response: response
            )
        }

        let result = try await embed(
            model: model,
            value: testValue
        )

        let body = result.response?.body as? [String: String]
        #expect(body == ["foo": "bar"])
        #expect(result.response?.headers == ["foo": "bar"])
    }

    @Test("result.value echoes input")
    func resultIncludesValue() async throws {
        let model = TestEmbeddingModelV4 { _ in
            EmbeddingModelV4Result(embeddings: [dummyEmbedding])
        }

        let result = try await embed(
            model: model,
            value: testValue
        )

        #expect(result.value == testValue)
    }

    @Test("result.usage reflects provider usage")
    func resultIncludesUsage() async throws {
        let model = TestEmbeddingModelV4 { _ in
            EmbeddingModelV4Result(
                embeddings: [dummyEmbedding],
                usage: EmbeddingModelV4Usage(tokens: 10)
            )
        }

        let result = try await embed(
            model: model,
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

        let model = TestEmbeddingModelV4 { _ in
            EmbeddingModelV4Result(
                embeddings: [dummyEmbedding],
                providerMetadata: providerMetadata
            )
        }

        let result = try await embed(
            model: model,
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
            model: model,
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

        let model = TestEmbeddingModelV4 { options in
            await capturedHeaders.set(options.headers)
            return EmbeddingModelV4Result(embeddings: [dummyEmbedding])
        }

        let result = try await embed(
            model: model,
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

        let model = TestEmbeddingModelV4 { options in
            #expect(options.providerOptions == expectedOptions)
            return EmbeddingModelV4Result(embeddings: [[1, 2, 3]])
        }

        let result = try await embed(
            model: model,
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
                model: 
                    TestEmbeddingModelV4 { _ in
                        EmbeddingModelV4Result(embeddings: [dummyEmbedding])
                    },
                value: testValue,
                telemetry: TelemetryOptions(isEnabled: false, integrations: [OpenTelemetry(tracer: tracer, embedding: true, runtimeContext: true)])
            ) as DefaultEmbedResult<String>

        #expect(tracer.spanRecords.isEmpty)
    }

    @Test("telemetry enabled records expected spans")
    func telemetryEnabledRecordsSpans() async throws {
        let tracer = MockTracer()

        _ =
            try await embed(
                model: 
                    TestEmbeddingModelV4 { _ in
                        EmbeddingModelV4Result(
                            embeddings: [dummyEmbedding],
                            usage: EmbeddingModelV4Usage(tokens: 10)
                        )
                    },
                value: testValue,
                telemetry: TelemetryOptions(
                    functionId: "test-function-id",
                    includeRuntimeContext: ["tenant": true],
                    integrations: [OpenTelemetry(tracer: tracer, embedding: true, runtimeContext: true)]
                ),
                runtimeContext: ["tenant": .string("acme"), "secret": .string("hidden")]
            ) as DefaultEmbedResult<String>

        let spans = tracer.spanRecords
        #expect(spans.map(\.name) == ["embeddings test-model", "embeddings test-model"])
        let outer = try #require(spans.first)
        let inner = try #require(spans.last)
        #expect(inner.parentId == outer.spanId)
        #expect(spans.allSatisfy { $0.ended && $0.kind == .client })
        #expect(outer.attributes["gen_ai.request.model"] == .string("test-model"))
        #expect(outer.attributes["gen_ai.provider.name"] == .string("test-provider"))
        #expect(outer.attributes["gen_ai.operation.name"] == .string("embeddings"))
        #expect(outer.attributes["ai.value"] == .string("\"sunny day at the beach\""))
        #expect(outer.attributes["ai.embedding"] == .string("[0.1,0.2,0.3]"))
        #expect(outer.attributes["ai.settings.context.tenant"] == .string("acme"))
        #expect(outer.attributes["ai.settings.context.secret"] == nil)
        #expect(inner.attributes["ai.values"] == .stringArray(["\"sunny day at the beach\""]))
        #expect(inner.attributes["ai.embeddings"] == .stringArray(["[0.1,0.2,0.3]"]))
        #expect(inner.attributes["gen_ai.usage.input_tokens"] == .int(10))
    }

    @Test("telemetry respects recordInputs and recordOutputs flags")
    func telemetryRespectsRecordFlags() async throws {
        let tracer = MockTracer()

        _ =
            try await embed(
                model: 
                    TestEmbeddingModelV4 { _ in
                        EmbeddingModelV4Result(
                            embeddings: [dummyEmbedding],
                            usage: EmbeddingModelV4Usage(tokens: 10)
                        )
                    },
                value: testValue,
                telemetry: TelemetryOptions(
                    recordInputs: false,
                    recordOutputs: false,
                    integrations: [OpenTelemetry(tracer: tracer, embedding: true, runtimeContext: true)]
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

extension TestEmbeddingModelV4 {
    fileprivate convenience init(
        supportsParallelCalls: Bool = true,
        maxEmbeddingsPerCall: Int? = nil,
        doEmbed: @escaping @Sendable (EmbeddingModelV4CallOptions) async throws ->
            EmbeddingModelV4Result
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

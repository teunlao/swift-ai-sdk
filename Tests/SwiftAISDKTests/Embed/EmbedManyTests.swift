import AISDKProvider
import AISDKProviderUtils
import Foundation
import Testing

@testable import SwiftAISDK

/// Tests for the `embedMany` API.
///
/// Port of `@ai-sdk/ai/src/embed/embed-many.test.ts`.
@Suite("EmbedMany Tests")
struct EmbedManyTests {
    private let dummyEmbeddings: [Embedding] = [
        [0.1, 0.2, 0.3],
        [0.4, 0.5, 0.6],
        [0.7, 0.8, 0.9],
    ]

    private let testValues = [
        "sunny day at the beach",
        "rainy afternoon in the city",
        "snowy night in the mountains",
    ]

    // MARK: - Parallelisation behaviour

    @Test("does not parallelize when model does not support it")
    func noParallelizationWhenUnsupported() async throws {
        let events = EventRecorder()
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: false,
            maxEmbeddingsPerCall: 1
        ) { options in
            let startIndex = await callCounter.next()
            await events.append("start-\(startIndex)")
            try await Task.sleep(nanoseconds: 5_000_000)
            await events.append("end-\(startIndex)")

            let embeddingIndex = testValues.firstIndex(of: options.values[0])!

            return EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbeddings[embeddingIndex]],
                response: EmbeddingModelV3ResponseInfo()
            )
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        #expect(
            await events.snapshot() == [
                "start-0",
                "end-0",
                "start-1",
                "end-1",
                "start-2",
                "end-2",
            ])
        #expect(result.embeddings == dummyEmbeddings)
    }

    @Test("parallelizes when supported by the model")
    func parallelizesWhenSupported() async throws {
        let events = EventRecorder()
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: true,
            maxEmbeddingsPerCall: 1
        ) { options in
            let startIndex = await callCounter.next()
            await events.append("start-\(startIndex)")
            try await Task.sleep(nanoseconds: 5_000_000)
            await events.append("end-\(startIndex)")

            let embeddingIndex = testValues.firstIndex(of: options.values[0])!

            return EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbeddings[embeddingIndex]],
                response: EmbeddingModelV3ResponseInfo()
            )
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        let recorded = await events.snapshot()
        #expect(recorded.prefix(3) == ["start-0", "start-1", "start-2"])
        #expect(Set(recorded.suffix(3)) == Set(["end-0", "end-1", "end-2"]))
        // When parallelized, order may vary - check all embeddings are present
        let actualSet = Set(result.embeddings.map { String(describing: $0) })
        let expectedSet = Set(dummyEmbeddings.map { String(describing: $0) })
        #expect(actualSet == expectedSet)
    }

    @Test("respects maxParallelCalls limit")
    func respectsMaxParallelCalls() async throws {
        let events = EventRecorder()
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: true,
            maxEmbeddingsPerCall: 1
        ) { options in
            let startIndex = await callCounter.next()
            await events.append("start-\(startIndex)")
            try await Task.sleep(nanoseconds: 5_000_000)
            await events.append("end-\(startIndex)")

            let embeddingIndex = testValues.firstIndex(of: options.values[0])!

            return EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbeddings[embeddingIndex]],
                response: EmbeddingModelV3ResponseInfo()
            )
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues,
            maxParallelCalls: 2
        )

        let recorded = await events.snapshot()
        #expect(recorded.count == 6)
        #expect(Set(recorded.prefix(2)) == Set(["start-0", "start-1"]))
        #expect(Set(recorded[2..<4]) == Set(["end-0", "end-1"]))
        #expect(recorded[4] == "start-2")
        #expect(recorded[5] == "end-2")
        #expect(result.embeddings == dummyEmbeddings)
    }

    // MARK: - Result content

    @Test("result.embeddings populated for single-call path")
    func embeddingsSingleCall() async throws {
        let model = TestEmbeddingModelV3<String>(
            maxEmbeddingsPerCall: nil
        ) { _ in
            EmbeddingModelV3DoEmbedResult(embeddings: dummyEmbeddings)
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        #expect(result.embeddings == dummyEmbeddings)
    }

    @Test("result.embeddings aggregated across multiple calls")
    func embeddingsMultipleCalls() async throws {
        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: false,
            maxEmbeddingsPerCall: 2
        ) { options in
            if options.values == Array(testValues.prefix(2)) {
                return EmbeddingModelV3DoEmbedResult(embeddings: Array(dummyEmbeddings.prefix(2)))
            }
            #expect(options.values == Array(testValues.suffix(1)))
            return EmbeddingModelV3DoEmbedResult(embeddings: Array(dummyEmbeddings.suffix(1)))
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        #expect(result.embeddings == dummyEmbeddings)
    }

    @Test("result.responses collects per-call responses")
    func responsesCollected() async throws {
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: false,
            maxEmbeddingsPerCall: 1
        ) { _ in
            let index = await callCounter.next()
            return EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbeddings[index]],
                response: EmbeddingModelV3ResponseInfo(
                    body: ["index": index]
                )
            )
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        let bodies = result.responses?.compactMap { $0?.body as? [String: Int] } ?? []
        #expect(
            bodies == [
                ["index": 0],
                ["index": 1],
                ["index": 2],
            ])
    }

    @Test("result.values mirrors input order")
    func resultValuesMatchInput() async throws {
        let model = TestEmbeddingModelV3<String> { _ in
            EmbeddingModelV3DoEmbedResult(embeddings: dummyEmbeddings)
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        #expect(result.values == testValues)
    }

    @Test("result.usage aggregates tokens")
    func usageAggregated() async throws {
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: false,
            maxEmbeddingsPerCall: 2
        ) { _ in
            let index = await callCounter.next()
            return EmbeddingModelV3DoEmbedResult(
                embeddings: index == 0
                    ? Array(dummyEmbeddings.prefix(2)) : Array(dummyEmbeddings.suffix(1)),
                usage: EmbeddingModelV3Usage(tokens: index == 0 ? 10 : 20)
            )
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        #expect(result.usage == EmbeddingModelUsage(tokens: 30))
    }

    @Test("headers option forwarded to provider")
    func headersForwarded() async throws {
        let capturedHeaders = HeadersCapture()

        let model = TestEmbeddingModelV3<String>(
            maxEmbeddingsPerCall: nil
        ) { options in
            await capturedHeaders.set(options.headers)
            return EmbeddingModelV3DoEmbedResult(embeddings: dummyEmbeddings)
        }

        _ =
            try await embedMany(
                model: .v3(model),
                values: testValues,
                headers: ["custom-request-header": "request-header-value"]
            ) as DefaultEmbedManyResult<String>

        let headers: [String: String]? = await capturedHeaders.get()
        let expected: [String: String] = [
            "custom-request-header": "request-header-value",
            "user-agent": "ai/\(VERSION)",
        ]
        #expect(headers == expected)
    }

    @Test("providerOptions forwarded to provider")
    func providerOptionsForwarded() async throws {
        let expected: ProviderOptions = [
            "aProvider": ["someKey": .string("someValue")]
        ]

        let model = TestEmbeddingModelV3<String>(
            maxEmbeddingsPerCall: nil
        ) { options in
            #expect(options.providerOptions == expected)
            return EmbeddingModelV3DoEmbedResult(embeddings: [[1, 2, 3]])
        }

        _ =
            try await embedMany(
                model: .v3(model),
                values: ["test-input"],
                providerOptions: expected
            ) as DefaultEmbedManyResult<String>
    }

    @Test("provider metadata merged across calls")
    func providerMetadataMerged() async throws {
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: false,
            maxEmbeddingsPerCall: 1
        ) { _ in
            let index = await callCounter.next()

            let metadata: ProviderMetadata = [
                "gateway": [
                    "call\(index)": .bool(true)
                ]
            ]

            return EmbeddingModelV3DoEmbedResult(
                embeddings: [dummyEmbeddings[index]],
                providerMetadata: metadata
            )
        }

        let result = try await embedMany(
            model: .v3(model),
            values: testValues
        )

        #expect(
            result.providerMetadata == [
                "gateway": [
                    "call0": .bool(true),
                    "call1": .bool(true),
                    "call2": .bool(true),
                ]
            ])
    }

    // MARK: - Telemetry

    @Test("telemetry disabled records no spans")
    func telemetryDisabledRecordsNoSpans() async throws {
        let tracer = MockTracer()

        _ =
            try await embedMany(
                model: .v3(
                    TestEmbeddingModelV3<String> { _ in
                        EmbeddingModelV3DoEmbedResult(embeddings: dummyEmbeddings)
                    }
                ),
                values: testValues,
                experimentalTelemetry: TelemetrySettings(tracer: tracer)
            ) as DefaultEmbedManyResult<String>

        #expect(tracer.spanRecords.isEmpty)
    }

    @Test("telemetry enabled records spans for multi-call path")
    func telemetryEnabledMultiCall() async throws {
        let tracer = MockTracer()
        let callCounter = CallCounter()

        let model = TestEmbeddingModelV3<String>(
            supportsParallelCalls: false,
            maxEmbeddingsPerCall: 2
        ) { _ in
            let index = await callCounter.next()
            return EmbeddingModelV3DoEmbedResult(
                embeddings: index == 0
                    ? Array(dummyEmbeddings.prefix(2)) : Array(dummyEmbeddings.suffix(1)),
                usage: EmbeddingModelV3Usage(tokens: index == 0 ? 10 : 20)
            )
        }

        _ =
            try await embedMany(
                model: .v3(model),
                values: testValues,
                experimentalTelemetry: TelemetrySettings(
                    isEnabled: true,
                    functionId: "test-function-id",
                    metadata: [
                        "test1": .string("value1"),
                        "test2": .bool(false),
                    ],
                    tracer: tracer
                )
            ) as DefaultEmbedManyResult<String>

        let spans = tracer.spanRecords
        #expect(spans.count == 3)

        if spans.count >= 3 {
            let outer = spans[0]
            #expect(outer.name == "ai.embedMany")
            #expect(outer.attributes["ai.usage.tokens"] == .int(30))
            #expect(
                outer.attributes["ai.values"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(from: testValues.map { $0 as Any })
                    )
            )

            let firstInner = spans[1]
            #expect(firstInner.name == "ai.embedMany.doEmbed")
            #expect(firstInner.attributes["ai.usage.tokens"] == .int(10))
            #expect(
                firstInner.attributes["ai.values"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(
                            from: Array(testValues.prefix(2)).map { $0 as Any })
                    )
            )

            let secondInner = spans[2]
            #expect(secondInner.attributes["ai.usage.tokens"] == .int(20))
            #expect(
                secondInner.attributes["ai.values"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(from: [testValues[2] as Any])
                    )
            )
        }
    }

    @Test("telemetry enabled records spans for single-call path")
    func telemetryEnabledSingleCall() async throws {
        let tracer = MockTracer()

        _ =
            try await embedMany(
                model: .v3(
                    TestEmbeddingModelV3<String>(
                        maxEmbeddingsPerCall: nil
                    ) { _ in
                        EmbeddingModelV3DoEmbedResult(
                            embeddings: dummyEmbeddings,
                            usage: EmbeddingModelV3Usage(tokens: 10)
                        )
                    }
                ),
                values: testValues,
                experimentalTelemetry: TelemetrySettings(
                    isEnabled: true,
                    functionId: "test-function-id",
                    tracer: tracer
                )
            ) as DefaultEmbedManyResult<String>

        let spans = tracer.spanRecords
        #expect(spans.count == 2)

        if spans.count >= 2 {
            let outer = spans[0]
            #expect(outer.attributes["ai.usage.tokens"] == .int(10))
            #expect(
                outer.attributes["ai.values"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(from: testValues.map { $0 as Any })
                    )
            )

            let inner = spans[1]
            #expect(
                inner.attributes["ai.embeddings"]
                    == .stringArray(
                        embedTelemetryJSONStringArray(from: dummyEmbeddings.map { $0 as Any })
                    )
            )
            #expect(inner.attributes["ai.usage.tokens"] == .int(10))
        }
    }

    @Test("telemetry respects recordInputs and recordOutputs flags")
    func telemetryRespectsRecordFlags() async throws {
        let tracer = MockTracer()

        _ =
            try await embedMany(
                model: .v3(
                    TestEmbeddingModelV3<String>(
                        maxEmbeddingsPerCall: nil
                    ) { _ in
                        EmbeddingModelV3DoEmbedResult(
                            embeddings: dummyEmbeddings,
                            usage: EmbeddingModelV3Usage(tokens: 10)
                        )
                    }
                ),
                values: testValues,
                experimentalTelemetry: TelemetrySettings(
                    isEnabled: true,
                    recordInputs: false,
                    recordOutputs: false,
                    tracer: tracer
                )
            ) as DefaultEmbedManyResult<String>

        let spans = tracer.spanRecords
        #expect(spans.count == 2)

        if spans.count >= 2 {
            let outer = spans[0]
            #expect(outer.attributes["ai.values"] == nil)
            #expect(outer.attributes["ai.embeddings"] == nil)

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

private actor EventRecorder {
    private var events: [String] = []

    func append(_ event: String) {
        events.append(event)
    }

    func snapshot() -> [String] {
        events
    }
}

private actor CallCounter {
    private var value = 0

    func next() -> Int {
        let current = value
        value += 1
        return current
    }
}

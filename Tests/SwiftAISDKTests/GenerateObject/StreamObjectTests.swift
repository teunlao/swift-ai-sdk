import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
@testable import AISDKProviderUtils

@Suite("streamObject")
struct StreamObjectTests {
    private let defaultUsage = LanguageModelUsage(
        inputTokens: 3,
        outputTokens: 10,
        totalTokens: 13,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    private func defaultObjectSchema() -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(
                .object([
                    "$schema": .string("http://json-schema.org/draft-07/schema#"),
                    "type": .string("object"),
                    "properties": .object([
                        "content": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("content")]),
                    "additionalProperties": .bool(false)
                ])
            )
        )
    }

    @Test("object output streams partial updates")
    func objectOutputEmitsDeltas() async throws {
        let model = MockStreamLanguageModel(
            parts: defaultParts()
        )

        let result = try streamObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        let partials = try await convertAsyncIterableToArray(result.partialObjectStream)
        #expect(partials == [
            [:],
            ["content": .string("Hello, ")],
            ["content": .string("Hello, world")],
            ["content": .string("Hello, world!")]
        ])

        let call = await model.waitForFirstCall()

        let resolvedSchema = try await defaultObjectSchema().resolve().jsonSchema()
        #expect(call.options.responseFormat == .json(schema: resolvedSchema, name: nil, description: nil))
    }

    @Test("object output propagates schema metadata")
    func objectOutputUsesSchemaMetadata() async throws {
        let model = MockStreamLanguageModel(parts: defaultParts())

        let _ = try streamObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(
                schema: defaultObjectSchema(),
                schemaName: "test-name",
                schemaDescription: "test description"
            ),
            prompt: "prompt"
        )

        let call = await model.waitForFirstCall()

        let resolvedSchema = try await defaultObjectSchema().resolve().jsonSchema()
        #expect(call.options.responseFormat == .json(schema: resolvedSchema, name: "test-name", description: "test description"))
    }

    @Test("array output exposes element stream")
    func arrayOutputElementStream() async throws {
        let model = MockStreamLanguageModel(parts: arrayParts())

        let elementSchema: FlexibleSchema<Int> = FlexibleSchema(
            jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("value")]),
                    "additionalProperties": .bool(false)
                ])
            ) { value in
                guard let dictionary = value as? [String: Any],
                      let stringValue = dictionary["value"] as? String,
                      let intValue = Int(stringValue) else {
                    let error = SchemaTypeMismatchError(expected: Int.self, actual: value)
                    let wrapped = TypeValidationError.wrap(value: value, cause: error)
                    return .failure(error: wrapped)
                }
                return .success(value: intValue)
            }
        )

        let result = try streamObject(
            model: .v3(model),
            output: GenerateObjectOutput.array(schema: elementSchema, schemaName: "array"),
            prompt: "prompt"
        )

        let elements = try await convertAsyncIterableToArray(result.elementStream)
        #expect(elements == [1, 2, 3])
    }

    @Test("onFinish receives metadata and object")
    func onFinishReceivesMetadata() async throws {
        let model = MockStreamLanguageModel(parts: defaultParts())
        let finishCollector = FinishEventCollector<JSONValue>()

        let result = try streamObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            onFinish: { event in
                await finishCollector.set(event)
            }
        )

        _ = try await convertAsyncIterableToArray(result.partialObjectStream)

        let event = await finishCollector.wait()
        #expect(event.usage == defaultUsage)
        #expect(event.finishReason == .stop)
        #expect(event.providerMetadata?["testProvider"]?["testKey"] == .string("testValue"))
        #expect(event.object == JSONValue.object(["content": .string("Hello, world!")]))
    }

    @Test("onError is invoked for parse errors")
    func onErrorTriggered() async throws {
        let errorModel = MockStreamLanguageModel(parts: [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-1", modelId: "mock", timestamp: Date(timeIntervalSince1970: 0)),
            .textDelta(id: "1", delta: "{", providerMetadata: nil),
            .error(error: .string("broken-json"))
        ])

        let errorCollector = ErrorEventCollector()

        let result = try? streamObject(
            model: .v3(errorModel),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            onError: { event in
                await errorCollector.append(event)
            }
        )

        #expect(result != nil)
        let _ = await errorCollector.next()
    }

    @Test("textStream emits raw chunks")
    func textStreamEmitsChunks() async throws {
        let model = MockStreamLanguageModel(parts: defaultParts())

        let result = try streamObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        let text = try await convertAsyncIterableToArray(result.textStream)
        #expect(text == ["{ ", "\"content\": \"Hello, ", "world", "!\"", " }"])
    }

    // MARK: - Helpers

    private func defaultParts() -> [LanguageModelV3StreamPart] {
        [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date(timeIntervalSince1970: 0)),
            .textStart(id: "1", providerMetadata: nil),
            .textDelta(id: "1", delta: "{ ", providerMetadata: nil),
            .textDelta(id: "1", delta: "\"content\": ", providerMetadata: nil),
            .textDelta(id: "1", delta: "\"Hello, ", providerMetadata: nil),
            .textDelta(id: "1", delta: "world", providerMetadata: nil),
            .textDelta(id: "1", delta: "!\"", providerMetadata: nil),
            .textDelta(id: "1", delta: " }", providerMetadata: nil),
            .textEnd(id: "1", providerMetadata: nil),
            .finish(
                finishReason: .stop,
                usage: defaultUsage,
                providerMetadata: ["testProvider": ["testKey": .string("testValue")]]
            )
        ]
    }

    private func arrayParts() -> [LanguageModelV3StreamPart] {
        [
            .streamStart(warnings: []),
            .responseMetadata(id: "id-0", modelId: "mock-model-id", timestamp: Date()),
            .textDelta(id: "1", delta: "{ \"elements\": [", providerMetadata: nil),
            .textDelta(id: "1", delta: "{\"value\":\"1\"}", providerMetadata: nil),
            .textDelta(id: "1", delta: ",", providerMetadata: nil),
            .textDelta(id: "1", delta: "{\"value\":\"2\"}", providerMetadata: nil),
            .textDelta(id: "1", delta: ",", providerMetadata: nil),
            .textDelta(id: "1", delta: "{\"value\":\"3\"}", providerMetadata: nil),
            .textDelta(id: "1", delta: "]}", providerMetadata: nil),
            .finish(finishReason: .stop, usage: defaultUsage, providerMetadata: nil)
        ]
    }
}

// MARK: - Test utilities

private final class MockStreamLanguageModel: LanguageModelV3, @unchecked Sendable {
    let provider: String = "mock-provider"
    let modelId: String = "mock-model-id"

    struct DoStreamCall {
        let options: LanguageModelV3CallOptions
    }

    private actor CallRecorder {
        var calls: [DoStreamCall] = []
        var waiters: [CheckedContinuation<DoStreamCall, Never>] = []

        func append(_ call: DoStreamCall) {
            calls.append(call)
            for waiter in waiters {
                waiter.resume(returning: call)
            }
            waiters.removeAll()
        }

        func first() -> DoStreamCall? {
            calls.first
        }

        func waitForFirst() async -> DoStreamCall {
            if let first = calls.first {
                return first
            }
            return await withCheckedContinuation { continuation in
                waiters.append(continuation)
            }
        }
    }

    private let recorder = CallRecorder()

    private let parts: [LanguageModelV3StreamPart]
    private let requestInfo: LanguageModelV3RequestInfo?
    private let responseInfo: LanguageModelV3StreamResponseInfo?

    init(
        parts: [LanguageModelV3StreamPart],
        request: LanguageModelV3RequestInfo? = nil,
        response: LanguageModelV3StreamResponseInfo? = nil
    ) {
        self.parts = parts
        self.requestInfo = request
        self.responseInfo = response
    }

    func waitForFirstCall() async -> DoStreamCall {
        await recorder.waitForFirst()
    }

    var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            ["*/*": [try NSRegularExpression(pattern: ".*")]]
        }
    }

    func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        throw NotImplementedError()
    }

    func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        await recorder.append(DoStreamCall(options: options))
        return LanguageModelV3StreamResult(
            stream: AsyncThrowingStream { continuation in
                for part in parts {
                    continuation.yield(part)
                }
                continuation.finish()
            },
            request: requestInfo,
            response: responseInfo
        )
    }
}

private actor ErrorEventCollector {
    private var pending: [StreamObjectErrorEvent] = []
    private var waiters: [CheckedContinuation<StreamObjectErrorEvent, Never>] = []

    func append(_ event: StreamObjectErrorEvent) {
        pending.append(event)
        for waiter in waiters {
            waiter.resume(returning: event)
        }
        waiters.removeAll()
    }

    func next() async -> StreamObjectErrorEvent {
        if let first = pending.first {
            return first
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

private actor FinishEventCollector<ResultValue: Sendable> {
    private var storedEvent: StreamObjectFinishEvent<ResultValue>?
    private var waiters: [CheckedContinuation<StreamObjectFinishEvent<ResultValue>, Never>] = []

    func set(_ event: StreamObjectFinishEvent<ResultValue>) {
        storedEvent = event
        for waiter in waiters {
            waiter.resume(returning: event)
        }
        waiters.removeAll()
    }

    func wait() async -> StreamObjectFinishEvent<ResultValue> {
        if let event = storedEvent {
            return event
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }
}

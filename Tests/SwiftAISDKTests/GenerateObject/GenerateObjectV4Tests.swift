import Foundation
import Testing
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("GenerateObject V4 Tests")
struct GenerateObjectV4Tests {
    private actor CapturedGenerateOptions {
        private var value: LanguageModelV4CallOptions?

        func record(_ options: LanguageModelV4CallOptions) {
            value = options
        }

        func recorded() -> LanguageModelV4CallOptions? {
            value
        }
    }

    private actor CapturedStreamOptions {
        private var value: LanguageModelV4CallOptions?

        func record(_ options: LanguageModelV4CallOptions) {
            value = options
        }

        func recorded() -> LanguageModelV4CallOptions? {
            value
        }
    }

    private func defaultObjectSchema() -> FlexibleSchema<JSONValue> {
        FlexibleSchema(jsonSchema(
            .object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "content": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("content")]),
                "additionalProperties": .bool(false)
            ])
        ))
    }

    @Test("generateObject calls V4 model with V4 prompt responseFormat and reasoning")
    func generateObjectUsesLanguageModelV4Contract() async throws {
        let captured = CapturedGenerateOptions()
        let responseDate = Date(timeIntervalSince1970: 1_700_000_001)
        let model = MockLanguageModelV4(
            provider: "mock-v4-provider",
            modelId: "mock-v4-object-model",
            doGenerate: .function { options in
                await captured.record(options)

                return LanguageModelV4GenerateResult(
                    content: [
                        .reasoning(LanguageModelV4Reasoning(text: "thinking in v4")),
                        .text(LanguageModelV4Text(text: "{ \"content\": \"Hello object V4\" }"))
                    ],
                    finishReason: LanguageModelV4FinishReason(unified: .stop, raw: "stop"),
                    usage: LanguageModelV4Usage(
                        inputTokens: .init(total: 4, cacheRead: 1),
                        outputTokens: .init(total: 6, reasoning: 2)
                    ),
                    providerMetadata: ["mock": ["finish": .string("generate-object")]],
                    request: LanguageModelV4RequestInfo(body: JSONValue.object(["mode": .string("v4-generate")])),
                    response: LanguageModelV4ResponseInfo(
                        id: "response-v4-object",
                        timestamp: responseDate,
                        modelId: "mock-v4-object-model",
                        headers: ["x-response": "v4"],
                        body: JSONValue.object(["ok": .bool(true)])
                    ),
                    warnings: [
                        .deprecated(setting: "temperature", message: "Use provider defaults.")
                    ]
                )
            }
        )

        let result: GenerateObjectResult<JSONValue> = try await generateObject(
            model: .v4(model),
            output: GenerateObjectOutput.object(
                schema: defaultObjectSchema(),
                schemaName: "object-result",
                schemaDescription: "Object result schema"
            ),
            system: "You are a V4 object test.",
            prompt: "Return an object.",
            providerOptions: ["mock": ["mode": .string("object")]],
            settings: CallSettings(
                temperature: 0.3,
                reasoning: .high,
                headers: ["x-test": "generate-object-v4"]
            )
        )

        let options = try #require(await captured.recorded())
        let resolvedSchema = try await defaultObjectSchema().resolve().jsonSchema()
        #expect(options.responseFormat == .json(
            schema: resolvedSchema,
            name: "object-result",
            description: "Object result schema"
        ))
        #expect(options.reasoning == .high)
        #expect(options.temperature == 0.3)
        #expect(options.headers?["x-test"] == "generate-object-v4")
        #expect(options.providerOptions?["mock"]?["mode"] == .string("object"))

        #expect(options.prompt.count == 2)
        if case .system(let content, _) = options.prompt[0] {
            #expect(content == "You are a V4 object test.")
        } else {
            Issue.record("Expected V4 system prompt")
        }
        if case .user(let content, _) = options.prompt[1],
           case .text(let textPart) = content.first {
            #expect(textPart.text == "Return an object.")
        } else {
            Issue.record("Expected V4 user text prompt")
        }

        #expect(result.object == .object(["content": .string("Hello object V4")]))
        #expect(result.reasoning == "thinking in v4")
        #expect(result.finishReason == .stop)
        #expect(result.usage.inputTokens == 4)
        #expect(result.usage.inputTokenDetails.cacheReadTokens == 1)
        #expect(result.usage.outputTokens == 6)
        #expect(result.usage.outputTokenDetails.reasoningTokens == 2)
        #expect(result.request.body == .object(["mode": .string("v4-generate")]))
        #expect(result.response.id == "response-v4-object")
        #expect(result.response.timestamp == responseDate)
        #expect(result.response.headers?["x-response"] == "v4")
        #expect(result.response.body == .object(["ok": .bool(true)]))
        #expect(result.providerMetadata?["mock"]?["finish"] == .string("generate-object"))

        let warning = try #require(result.warnings?.first)
        if case .deprecated(let setting, let message) = warning {
            #expect(setting == "temperature")
            #expect(message == "Use provider defaults.")
        } else {
            Issue.record("Expected V4 deprecated warning")
        }
    }

    @Test("streamObject calls V4 model with V4 prompt responseFormat and reasoning")
    func streamObjectUsesLanguageModelV4Contract() async throws {
        let captured = CapturedStreamOptions()
        let responseDate = Date(timeIntervalSince1970: 1_700_000_002)
        let model = MockLanguageModelV4(
            provider: "mock-v4-provider",
            modelId: "mock-v4-stream-object-model",
            doStream: .function { options in
                await captured.record(options)

                let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
                    continuation.yield(.streamStart(warnings: [
                        .deprecated(setting: "topK", message: "Use provider defaults.")
                    ]))
                    continuation.yield(.responseMetadata(
                        id: "response-v4-stream-object",
                        modelId: "mock-v4-stream-object-model",
                        timestamp: responseDate
                    ))
                    continuation.yield(.textDelta(id: "text-1", delta: "{ ", providerMetadata: nil))
                    continuation.yield(.custom(LanguageModelV4CustomContent(kind: "ignored-by-object-stream")))
                    continuation.yield(.reasoningFile(LanguageModelV4ReasoningFile(
                        mediaType: "text/plain",
                        data: .base64("cmVhc29uaW5n")
                    )))
                    continuation.yield(.textDelta(id: "text-1", delta: "\"content\": \"Hello stream V4\"", providerMetadata: nil))
                    continuation.yield(.textDelta(id: "text-1", delta: " }", providerMetadata: nil))
                    continuation.yield(.finish(
                        finishReason: LanguageModelV4FinishReason(unified: .stop, raw: "stop"),
                        usage: LanguageModelV4Usage(
                            inputTokens: .init(total: 5),
                            outputTokens: .init(total: 8, reasoning: 3)
                        ),
                        providerMetadata: ["mock": ["finish": .string("stream-object")]]
                    ))
                    continuation.finish()
                }

                return LanguageModelV4StreamResult(
                    stream: stream,
                    request: LanguageModelV4RequestInfo(body: JSONValue.object(["mode": .string("v4-stream-object")])),
                    response: LanguageModelV4StreamResponseInfo(headers: ["x-response": "stream-v4"])
                )
            }
        )

        let result = try streamObject(
            model: .v4(model),
            output: GenerateObjectOutput.object(
                schema: defaultObjectSchema(),
                schemaName: "stream-object-result",
                schemaDescription: "Stream object schema"
            ),
            system: "You are a V4 stream object test.",
            prompt: "Stream an object.",
            providerOptions: ["mock": ["mode": .string("stream-object")]],
            settings: CallSettings(
                temperature: 0.4,
                reasoning: .medium,
                headers: ["x-test": "stream-object-v4"]
            )
        )

        let partials = try await convertAsyncIterableToArray(result.partialObjectStream)
        let object = try await result.object
        let usage = try await result.usage
        let warnings = try await result.warnings
        let request = try await result.request
        let response = try await result.response
        let providerMetadata = try await result.providerMetadata
        let options = try #require(await captured.recorded())
        let resolvedSchema = try await defaultObjectSchema().resolve().jsonSchema()

        #expect(options.responseFormat == .json(
            schema: resolvedSchema,
            name: "stream-object-result",
            description: "Stream object schema"
        ))
        #expect(options.reasoning == .medium)
        #expect(options.temperature == 0.4)
        #expect(options.headers?["x-test"] == "stream-object-v4")
        #expect(options.providerOptions?["mock"]?["mode"] == .string("stream-object"))
        #expect(options.prompt.count == 2)

        #expect(partials.last == ["content": .string("Hello stream V4")])
        #expect(object == .object(["content": .string("Hello stream V4")]))
        #expect(usage.inputTokens == 5)
        #expect(usage.outputTokens == 8)
        #expect(usage.outputTokenDetails.reasoningTokens == 3)
        #expect(request.body == .object(["mode": .string("v4-stream-object")]))
        #expect(response.id == "response-v4-stream-object")
        #expect(response.timestamp == responseDate)
        #expect(response.headers?["x-response"] == "stream-v4")
        #expect(providerMetadata?["mock"]?["finish"] == .string("stream-object"))

        let warning = try #require(warnings?.first)
        if case .deprecated(let setting, let message) = warning {
            #expect(setting == "topK")
            #expect(message == "Use provider defaults.")
        } else {
            Issue.record("Expected V4 deprecated warning")
        }
    }
}

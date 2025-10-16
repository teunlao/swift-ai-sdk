import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
@testable import AISDKProviderUtils

@Suite("generateObject", .serialized)
struct GenerateObjectTests {
    private let dummyUsageV3 = LanguageModelV3Usage(
        inputTokens: 10,
        outputTokens: 20,
        totalTokens: 30,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    private let expectedUsage = LanguageModelUsage(
        inputTokens: 10,
        outputTokens: 20,
        totalTokens: 30,
        reasoningTokens: nil,
        cachedInputTokens: nil
    )

    private let dummyResponseInfo = LanguageModelV3ResponseInfo(
        id: "id-1",
        timestamp: Date(timeIntervalSince1970: 123),
        modelId: "m-1"
    )

    private func makeGenerateResult(
        content: [LanguageModelV3Content],
        finishReason: FinishReason = .stop,
        usage: LanguageModelV3Usage? = nil,
        warnings: [LanguageModelV3CallWarning] = [],
        request: LanguageModelV3RequestInfo? = nil,
        response: LanguageModelV3ResponseInfo? = nil,
        providerMetadata: ProviderMetadata? = nil
    ) -> LanguageModelV3GenerateResult {
        LanguageModelV3GenerateResult(
            content: content,
            finishReason: finishReason,
            usage: usage ?? dummyUsageV3,
            providerMetadata: providerMetadata,
            request: request,
            response: response ?? dummyResponseInfo,
            warnings: warnings
        )
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

    private final class WarningStorage: @unchecked Sendable {
        private let queue = DispatchQueue(label: "GenerateObjectTests.WarningStorage")
        private var values: [[Warning]] = []

        func append(_ warnings: [Warning]) {
            queue.sync {
                values.append(warnings)
            }
        }

        func snapshot() -> [[Warning]] {
            queue.sync { values }
        }
    }

    private func captureLoggedWarnings<T>(_ body: () async throws -> T) async rethrows -> (T, [[Warning]]) {
        let storage = WarningStorage()
        logWarningsObserver = { warnings in
            storage.append(warnings)
        }
        defer { logWarningsObserver = nil }
        let result = try await body()
        let captured = storage.snapshot()
        return (result, captured)
    }

    private func transformSchema() -> FlexibleSchema<[String: Int]> {
        FlexibleSchema(
            jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "content": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("content")]),
                    "additionalProperties": .bool(false)
                ])
            ) { value in
                guard let dictionary = value as? [String: Any],
                      let raw = dictionary["content"] as? String else {
                    let error = TypeValidationError.wrap(
                        value: value,
                        cause: SchemaTypeMismatchError(expected: String.self, actual: value)
                    )
                    return .failure(error: error)
                }
                return .success(value: ["content": raw.count])
            }
        )
    }

    private final class SupportedUrlsLanguageModel: LanguageModelV3 {
        let provider: String = "mock-provider"
        let modelId: String = "mock-model-id"
        nonisolated(unsafe) var supportedUrlsCalled = false
        let result: LanguageModelV3GenerateResult

        init(result: LanguageModelV3GenerateResult) {
            self.result = result
        }

        var supportedUrls: [String: [NSRegularExpression]] {
            get async throws {
                supportedUrlsCalled = (modelId == "mock-model-id")
                return ["image/*": [try NSRegularExpression(pattern: ".*")]]
            }
        }

        func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
            result
        }

        func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
            throw NotImplementedError()
        }
    }

    private func verifyNoObjectGeneratedError(_ error: any Error, message: String) {
        guard let error = error as? NoObjectGeneratedError else {
            Issue.record("Expected NoObjectGeneratedError")
            return
        }

        #expect(error.message == message)
        if let response = error.response {
            #expect(response.id == dummyResponseInfo.id)
            #expect(response.modelId == dummyResponseInfo.modelId)
            #expect(response.timestamp == dummyResponseInfo.timestamp)
        } else {
            Issue.record("Missing response metadata")
        }

        if let usage = error.usage {
            #expect(usage == expectedUsage)
        } else {
            Issue.record("Missing usage metadata")
        }

        #expect(error.finishReason == .stop)
    }

    private func preprocessSchema() -> FlexibleSchema<[String: String]> {
        FlexibleSchema(
            jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "content": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("content")]),
                    "additionalProperties": .bool(false)
                ])
            ) { value in
                guard let dictionary = value as? [String: Any] else {
                    let error = TypeValidationError.wrap(
                        value: value,
                        cause: SchemaTypeMismatchError(expected: [String: Any].self, actual: value)
                    )
                    return .failure(error: error)
                }

                var result: [String: String] = [:]
                for (key, rawValue) in dictionary {
                    if let stringValue = rawValue as? String {
                        result[key] = stringValue
                    } else if let numberValue = rawValue as? NSNumber {
                        result[key] = numberValue.stringValue
                    } else {
                        let error = TypeValidationError.wrap(
                            value: rawValue,
                            cause: SchemaTypeMismatchError(expected: String.self, actual: rawValue)
                        )
                        return .failure(error: error)
                    }
                }

                return .success(value: result)
            }
        )
    }

    @Test("should generate object")
    func generatesObject() async throws {
        guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
            Issue.record("generateObject requires modern platform")
            return
        }

        let generateResult = makeGenerateResult(
            content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
        )

        let model = MockLanguageModelV3(doGenerate: .singleValue(generateResult))

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        #expect(result.object == .object(["content": .string("Hello, world!")]))
        #expect(result.finishReason == .stop)
        #expect(result.usage == expectedUsage)
        #expect(result.request.body == nil)
        #expect(model.doGenerateCalls.count == 1)
        #expect(result.response.modelId == dummyResponseInfo.modelId)
    }

    @Test("should use name and description")
    func usesNameAndDescription() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                let schema = try await self.defaultObjectSchema().resolve().jsonSchema()
                #expect(options.responseFormat == .json(
                    schema: schema,
                    name: "test-name",
                    description: "test description"
                ))
                return self.makeGenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
                )
            }
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(
                schema: defaultObjectSchema(),
                schemaName: "test-name",
                schemaDescription: "test description"
            ),
            prompt: "prompt"
        )

        #expect(result.object == .object(["content": .string("Hello, world!")]))
        #expect(model.doGenerateCalls.count == 1)
    }

    @Test("should return warnings")
    func returnsWarnings() async throws {
        let warnings: [LanguageModelV3CallWarning] = [
            .other(message: "Setting is not supported")
        ]

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                warnings: warnings
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        #expect(result.warnings == warnings)
    }

    @Test("should call logWarnings with the correct warnings")
    func logsWarnings() async throws {
        let expectedWarnings: [LanguageModelV3CallWarning] = [
            .other(message: "Setting is not supported"),
            .unsupportedSetting(setting: "temperature", details: "Temperature parameter not supported")
        ]

        let (_, logged) = try await captureLoggedWarnings {
            try await generateObject(
                model: .v3(MockLanguageModelV3(
                    doGenerate: .singleValue(makeGenerateResult(
                        content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                        warnings: expectedWarnings
                    ))
                )),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt"
            )
        }

        let expectedEntry = expectedWarnings.map { Warning.languageModel($0) }
        #expect(logged.contains(expectedEntry))
    }

    @Test("should call logWarnings with empty array when no warnings are present")
    func logsEmptyWarnings() async throws {
        let (_, logged) = try await captureLoggedWarnings {
            try await generateObject(
                model: .v3(MockLanguageModelV3(
                    doGenerate: .singleValue(makeGenerateResult(
                        content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                        warnings: []
                    ))
                )),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt"
            )
        }

        #expect(logged.contains([]))
    }

    @Test("should contain request information")
    func resultContainsRequestMetadata() async throws {
        let requestInfo = LanguageModelV3RequestInfo(body: "test body")
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                request: requestInfo
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        #expect(result.request.body == .string("test body"))
    }

    @Test("should contain response information")
    func resultContainsResponseMetadata() async throws {
        let response = LanguageModelV3ResponseInfo(
            id: "test-id-from-model",
            timestamp: Date(timeIntervalSince1970: 10),
            modelId: "test-response-model-id",
            headers: [
                "custom-response-header": "response-header-value",
                "user-agent": "ai/\(VERSION)"
            ],
            body: "test body"
        )

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                response: response
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        #expect(result.response.id == "test-id-from-model")
        #expect(result.response.timestamp == Date(timeIntervalSince1970: 10))
        #expect(result.response.modelId == "test-response-model-id")
        #expect(result.response.headers?["custom-response-header"] == "response-header-value")
        #expect(result.response.body == .string("test body"))
    }

    @Test("should generate object with custom schema")
    func generatesObjectWithCustomSchema() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
            ))
        )

        let customSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "content": .object(["type": .string("string")])
                ]),
                "required": .array([.string("content")]),
                "additionalProperties": .bool(false)
            ])
        ))

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: customSchema),
            prompt: "prompt"
        )

        #expect(result.object == .object(["content": .string("Hello, world!")]))
    }

    @Test("should generate object when using transform schema")
    func generatesObjectWithTransformSchema() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            schema: transformSchema(),
            prompt: "prompt"
        )

        #expect(result.object == ["content": 13])
    }


    @Test("should generate object when using preprocess schema")
    func generatesObjectWithPreprocessSchema() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": 42 }"))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            schema: preprocessSchema(),
            prompt: "prompt"
        )

        #expect(result.object == ["content": "42"])
    }

    @Test("should return JSON response")
    func jsonResponse() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        let response = result.toJsonResponse()
        #expect(response.status == 200)
        #expect(response.headers["content-type"] == "application/json; charset=utf-8")
        #expect(String(data: response.body, encoding: .utf8) == "{\"content\":\"Hello, world!\"}")
    }

    @Test("should contain provider metadata")
    func resultContainsProviderMetadata() async throws {
        let metadata: ProviderMetadata = ["exampleProvider": ["a": 10, "b": 20]]
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                providerMetadata: metadata
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        #expect(result.providerMetadata == metadata)
    }

    @Test("should pass headers to model")
    func passesHeadersToModel() async throws {
        let headers: [String: String] = ["custom-request-header": "request-header-value"]
        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                #expect(options.headers?["custom-request-header"] == "request-header-value")
                #expect(options.headers?["user-agent"] == "ai/\(VERSION)")
                return self.makeGenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{ \"content\": \"headers test\" }"))]
                )
            }
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            settings: CallSettings(headers: headers)
        )

        #expect(result.object == .object(["content": .string("headers test")]))
        #expect(model.doGenerateCalls.count == 1)
    }

    @Test("should repair JSON parse errors")
    func repairsJSONParseError() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"provider metadata test\" "))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            experimentalRepairText: { options in
                #expect(options.text == "{ \"content\": \"provider metadata test\" ")
                if case .parse = options.error { } else { Issue.record("Expected parse error") }
                return options.text + "}"
            }
        )

        #expect(result.object == .object(["content": .string("provider metadata test")]))
    }

    @Test("should repair validation errors")
    func repairsValidationError() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content-a\": \"provider metadata test\" }"))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            experimentalRepairText: { options in
                if case .validation = options.error { } else { Issue.record("Expected validation error") }
                return "{ \"content\": \"provider metadata test\" }"
            }
        )

        #expect(result.object == .object(["content": .string("provider metadata test")]))
    }

    @Test("should tolerate repair returning nil")
    func repairReturnsNil() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content-a\": \"provider metadata test\" }"))]
            ))
        )

        await #expect(throws: NoObjectGeneratedError.self) {
            _ = try await generateObject(
                model: .v3(model),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt",
                experimentalRepairText: { _ in nil }
            )
        }
    }

    @Test("should pass provider options to model")
    func passesProviderOptions() async throws {
        let providerOptions: ProviderOptions = ["aProvider": ["someKey": .string("someValue")]]

        let model = MockLanguageModelV3(
            doGenerate: .function { options in
                #expect(options.providerOptions?["aProvider"]?["someKey"] == .string("someValue"))
                return self.makeGenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{ \"content\": \"provider options test\" }"))]
                )
            }
        )

        let result: GenerateObjectResult<JSONValue> = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            providerOptions: providerOptions
        )

        #expect(result.object == .object(["content": .string("provider options test")]))
        #expect(model.doGenerateCalls.count == 1)
    }
    
    @Test("should throw NoObjectGeneratedError when schema validation fails")
    func schemaValidationFailure() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": 123 }"))]
            ))
        )

        do {
            _ = try await generateObject(
                model: .v3(model),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt"
            ) as GenerateObjectResult<JSONValue>
            Issue.record("Expected NoObjectGeneratedError")
        } catch {
            verifyNoObjectGeneratedError(error, message: "No object generated: response did not match schema.")
        }
    }

    @Test("should throw NoObjectGeneratedError when parsing fails")
    func parsingFailure() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ broken json"))]
            ))
        )

        do {
            _ = try await generateObject(
                model: .v3(model),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt"
            ) as GenerateObjectResult<JSONValue>
            Issue.record("Expected NoObjectGeneratedError")
        } catch {
            verifyNoObjectGeneratedError(error, message: "No object generated: could not parse the response.")
        }
    }

    @Test("should throw NoObjectGeneratedError when parsing fails with repairText")
    func parsingFailureWithRepair() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ broken json"))]
            ))
        )

        do {
            _ = try await generateObject(
                model: .v3(model),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt",
                experimentalRepairText: { options in
                    #expect(options.text == "{ broken json")
                    return options.text + "{"
                }
            ) as GenerateObjectResult<JSONValue>
            Issue.record("Expected NoObjectGeneratedError")
        } catch {
            verifyNoObjectGeneratedError(error, message: "No object generated: could not parse the response.")
        }
    }

    @Test("should throw NoObjectGeneratedError when no text is available")
    func noTextAvailable() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: []
            ))
        )

        do {
            _ = try await generateObject(
                model: .v3(model),
                output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
                prompt: "prompt"
            ) as GenerateObjectResult<JSONValue>
            Issue.record("Expected NoObjectGeneratedError")
        } catch {
            verifyNoObjectGeneratedError(error, message: "No object generated: the model did not return a response.")
        }
    }

    @Test("should generate an array with 3 elements")
    func generatesArray() async throws {
        let arraySchema = FlexibleSchema(jsonSchema(
            .object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "content": .object(["type": .string("string")])
                ]),
                "required": .array([.string("content")]),
                "additionalProperties": .bool(false)
            ])
        ))

        let expectedElements: [[String: JSONValue]] = [
            ["content": .string("element 1")],
            ["content": .string("element 2")],
            ["content": .string("element 3")]
        ]

        let jsonText = "{ \"elements\": [{\"content\":\"element 1\"},{\"content\":\"element 2\"},{\"content\":\"element 3\"}] }"

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: jsonText))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.array(schema: arraySchema),
            prompt: "prompt"
        )

        #expect(result.object == expectedElements.map { JSONValue.object($0) })
    }

    @Test("should generate an enum value")
    func generatesEnumValue() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"result\": \"sunny\" }"))]
            ))
        )

        let result: GenerateObjectResult<String> = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.enumeration(values: ["sunny", "rainy", "snowy"]),
            prompt: "prompt"
        )

        #expect(result.object == "sunny")
    }

    @Test("should generate object without schema")
    func generatesWithoutSchema() async throws {
        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
            ))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.noSchema(),
            prompt: "prompt"
        )

        #expect(result.object == .object(["content": .string("Hello, world!")]))
    }

    @Test("telemetry disabled does not record spans")
    func telemetryDisabledRecordsNoSpans() async throws {
        let tracer = MockTracer()

        _ = try await generateObject(
            model: .v3(MockLanguageModelV3(
                doGenerate: .singleValue(makeGenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
                ))
            )),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            experimentalTelemetry: TelemetrySettings(tracer: tracer)
        ) as GenerateObjectResult<JSONValue>

        #expect(tracer.spanRecords.isEmpty)
    }

    @Test("telemetry enabled records expected spans")
    func telemetryEnabledRecordsSpans() async throws {
        let tracer = MockTracer()
        let providerMetadata: ProviderMetadata = ["testProvider": ["testKey": .string("testValue")]]

        _ = try await generateObject(
            model: .v3(MockLanguageModelV3(
                doGenerate: .singleValue(makeGenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                    response: LanguageModelV3ResponseInfo(
                        id: "test-id-from-model",
                        timestamp: Date(timeIntervalSince1970: 10),
                        modelId: "test-response-model-id"
                    ),
                    providerMetadata: providerMetadata
                ))
            )),
            output: GenerateObjectOutput.object(
                schema: defaultObjectSchema(),
                schemaName: "test-name",
                schemaDescription: "test description"
            ),
            prompt: "prompt",
            experimentalTelemetry: TelemetrySettings(
                isEnabled: true,
                functionId: "test-function-id",
                metadata: [
                    "test1": .string("value1"),
                    "test2": .bool(false)
                ],
                tracer: tracer
            ),
            settings: CallSettings(
                temperature: 0.5,
                topP: 0.2,
                topK: 1,
                presencePenalty: 0.4,
                frequencyPenalty: 0.3,
                headers: ["header1": "value1", "header2": "value2"]
            )
        ) as GenerateObjectResult<JSONValue>

        let spans = tracer.spanRecords
        #expect(spans.count == 2)

        if spans.count == 2 {
            let outer = spans[0]
            #expect(outer.name == "ai.generateObject")
            #expect(outer.attributes["ai.model.id"] == .string("mock-model-id"))
            #expect(outer.attributes["ai.model.provider"] == .string("mock-provider"))
            #expect(outer.attributes["ai.operationId"] == .string("ai.generateObject"))
            #expect(outer.attributes["ai.request.headers.header1"] == .string("value1"))
            #expect(outer.attributes["ai.request.headers.header2"] == .string("value2"))
            #expect(outer.attributes["ai.request.headers.user-agent"] == .string("ai/\(VERSION)"))
            #expect(outer.attributes["ai.response.finishReason"] == .string("stop"))
            #expect(outer.attributes["ai.response.object"] == .string("{\"content\":\"Hello, world!\"}"))
            #expect(outer.attributes["ai.response.providerMetadata"] == .string("{\"testProvider\":{\"testKey\":\"testValue\"}}"))
            #expect(outer.attributes["ai.schema"] != nil)
            #expect(outer.attributes["ai.schema.name"] == .string("test-name"))
            #expect(outer.attributes["ai.schema.description"] == .string("test description"))
            #expect(outer.attributes["ai.telemetry.functionId"] == .string("test-function-id"))
            #expect(outer.attributes["ai.telemetry.metadata.test1"] == .string("value1"))
            #expect(outer.attributes["ai.telemetry.metadata.test2"] == .bool(false))
            #expect(outer.attributes["ai.settings.topK"] == .int(1))
            #expect(outer.attributes["ai.settings.topP"] == .double(0.2))
            #expect(outer.attributes["ai.settings.frequencyPenalty"] == .double(0.3))
            #expect(outer.attributes["ai.settings.presencePenalty"] == .double(0.4))
            #expect(outer.attributes["ai.usage.promptTokens"] == .int(10))
            #expect(outer.attributes["ai.usage.completionTokens"] == .int(20))

            let inner = spans[1]
            #expect(inner.name == "ai.generateObject.doGenerate")
            #expect(inner.attributes["gen_ai.request.model"] == .string("mock-model-id"))
            #expect(inner.attributes["gen_ai.system"] == .string("mock-provider"))
            #expect(inner.attributes["gen_ai.request.temperature"] == .double(0.5))
            #expect(inner.attributes["gen_ai.request.top_k"] == .int(1))
            #expect(inner.attributes["gen_ai.request.top_p"] == .double(0.2))
            #expect(inner.attributes["gen_ai.request.frequency_penalty"] == .double(0.3))
            #expect(inner.attributes["gen_ai.request.presence_penalty"] == .double(0.4))
            #expect(inner.attributes["ai.response.id"] == .string("test-id-from-model"))
            #expect(inner.attributes["ai.response.model"] == .string("test-response-model-id"))
            #expect(inner.attributes["ai.response.timestamp"] == .string("1970-01-01T00:00:10.000Z"))
            #expect(inner.attributes["ai.response.object"] == .string("{ \"content\": \"Hello, world!\" }"))
            #expect(inner.attributes["ai.response.providerMetadata"] == .string("{\"testProvider\":{\"testKey\":\"testValue\"}}"))
        }
    }

    @Test("telemetry with inputs/outputs disabled omits prompt and object")
    func telemetryOmitsInputsOutputs() async throws {
        let tracer = MockTracer()

        _ = try await generateObject(
            model: .v3(MockLanguageModelV3(
                doGenerate: .singleValue(makeGenerateResult(
                    content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))],
                    response: LanguageModelV3ResponseInfo(
                        id: "test-id-from-model",
                        timestamp: Date(timeIntervalSince1970: 10),
                        modelId: "test-response-model-id"
                    )
                ))
            )),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt",
            experimentalTelemetry: TelemetrySettings(
                isEnabled: true,
                recordInputs: false,
                recordOutputs: false,
                tracer: tracer
            )
        ) as GenerateObjectResult<JSONValue>

        let spans = tracer.spanRecords
        #expect(spans.count == 2)

        if spans.count == 2 {
            let outer = spans[0]
            #expect(outer.attributes["ai.prompt"] == nil)
            #expect(outer.attributes["ai.response.object"] == nil)

            let inner = spans[1]
            #expect(inner.attributes["ai.prompt.messages"] == nil)
            #expect(inner.attributes["ai.response.object"] == nil)
        }
    }

    @Test("should support models that reference self in supportedUrls")
    func supportedUrlsUsesSelf() async throws {
        let model = SupportedUrlsLanguageModel(
            result: makeGenerateResult(
                content: [.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))]
            )
        )

        let messages: [ModelMessage] = [
            .user(UserModelMessage(
                content: .parts([
                    .image(ImagePart(image: .url(URL(string: "https://example.com/test.jpg")!)))
                ]),
                providerOptions: nil
            ))
        ]

        let result: GenerateObjectResult<JSONValue> = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            messages: messages
        )

        #expect(result.object == .object(["content": .string("Hello, world!")]))
        #expect(model.supportedUrlsCalled)
    }

    @Test("should include reasoning in the result")
    func reasoningIncludedInResult() async throws {
        let reasoningContent = [
            LanguageModelV3Content.reasoning(LanguageModelV3Reasoning(text: "This is a test reasoning.")),
            LanguageModelV3Content.reasoning(LanguageModelV3Reasoning(text: "This is another test reasoning.")),
            LanguageModelV3Content.text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))
        ]

        let model = MockLanguageModelV3(
            doGenerate: .singleValue(makeGenerateResult(content: reasoningContent))
        )

        let result = try await generateObject(
            model: .v3(model),
            output: GenerateObjectOutput.object(schema: defaultObjectSchema()),
            prompt: "prompt"
        )

        #expect(result.reasoning == "This is a test reasoning.\nThis is another test reasoning.")
        #expect(result.object == .object(["content": .string("Hello, world!")]))
    }
}

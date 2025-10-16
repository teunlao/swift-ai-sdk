import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("generateObject")
struct GenerateObjectTests {
    private let modelUsageV3 = LanguageModelV3Usage(
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

    private func makeSchema() -> FlexibleSchema<JSONValue> {
        FlexibleSchema(
            jsonSchema(.object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "content": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([.string("content")]),
                "additionalProperties": .bool(false)
            ]))
        )
    }

    @Test("should generate object")
    func generatesObject() async throws {
        guard #available(macOS 13.0, iOS 16.0, watchOS 9.0, tvOS 16.0, *) else {
            Issue.record("generateObject requires modern platform")
            return
        }
        let generateResult = LanguageModelV3GenerateResult(
            content: [
                .text(LanguageModelV3Text(text: "{ \"content\": \"Hello, world!\" }"))
            ],
            finishReason: .stop,
            usage: modelUsageV3,
            providerMetadata: nil,
            request: LanguageModelV3RequestInfo(body: nil),
            response: LanguageModelV3ResponseInfo(
                id: "id-1",
                timestamp: Date(timeIntervalSince1970: 123),
                modelId: "mock-model-id"
            ),
            warnings: []
        )

        let mock = MockLanguageModelV3(
            doGenerate: .singleValue(generateResult)
        )

        let result = try await generateObject(
            model: .v3(mock),
            schema: makeSchema(),
            prompt: "prompt"
        )

        #expect(result.object == .object(["content": .string("Hello, world!")]))
        #expect(result.finishReason == .stop)
        #expect(result.usage == expectedUsage)
        #expect(result.request.body == nil)
        #expect(result.response.modelId == "mock-model-id")
    }
}


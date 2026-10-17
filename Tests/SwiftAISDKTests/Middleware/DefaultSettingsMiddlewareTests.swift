import Foundation
import Testing
import AISDKProvider
import SwiftAISDK

private func transform(
    _ settings: DefaultSettings,
    _ params: LanguageModelV4CallOptions
) async throws -> LanguageModelV4CallOptions {
    let middleware: LanguageModelV4Middleware = defaultSettingsMiddleware(settings: settings)
    return try await middleware.transformParams!(.generate, params, MockLanguageModelV4())
}

@Suite("defaultSettingsMiddleware")
struct DefaultSettingsMiddlewareTests {
    @Test("fills unset parameters from the defaults and lets set parameters win")
    func scalarPrecedence() async throws {
        let tool = LanguageModelV4Tool.function(LanguageModelV4FunctionTool(name: "weather", inputSchema: .object([:])))
        let result = try await transform(
            DefaultSettings(
                maxOutputTokens: 100,
                temperature: 0.7,
                stopSequences: ["stop"],
                topP: 0.9,
                seed: 1,
                tools: [tool],
                toolChoice: .required
            ),
            LanguageModelV4CallOptions(
                prompt: middlewareTestPrompt,
                temperature: 0,
                stopSequences: [],
                tools: [],
                reasoning: .high
            )
        )

        #expect(result.prompt == middlewareTestPrompt)
        #expect(result.maxOutputTokens == 100)
        #expect(result.temperature == 0)
        #expect(result.stopSequences == [])
        #expect(result.topP == 0.9)
        #expect(result.seed == 1)
        #expect(result.tools == [])
        #expect(result.toolChoice == .required)
        #expect(result.reasoning == .high)
    }

    @Test("deep-merges provider options and merges headers")
    func nestedMerge() async throws {
        let result = try await transform(
            DefaultSettings(
                headers: ["X-Default": "default", "X-Shared": "default"],
                providerOptions: [
                    "anthropic": [
                        "cacheControl": .object(["type": .string("ephemeral")]),
                        "tools": .object([
                            "retrieval": .object(["enabled": .bool(true)]),
                            "math": .object(["enabled": .bool(true)]),
                        ]),
                    ],
                    "openai": ["logit_bias": .object(["50256": .number(-100)])],
                ]
            ),
            LanguageModelV4CallOptions(
                prompt: middlewareTestPrompt,
                headers: ["X-Shared": "param", "X-Param": "param"],
                providerOptions: [
                    "anthropic": [
                        "tools": .object([
                            "retrieval": .object(["enabled": .bool(false)]),
                            "code": .object(["enabled": .bool(true)]),
                        ]),
                        "otherSetting": .string("value"),
                    ],
                ]
            )
        )

        #expect(result.headers == ["X-Default": "default", "X-Shared": "param", "X-Param": "param"])
        #expect(result.providerOptions == [
            "anthropic": [
                "cacheControl": .object(["type": .string("ephemeral")]),
                "tools": .object([
                    "retrieval": .object(["enabled": .bool(false)]),
                    "math": .object(["enabled": .bool(true)]),
                    "code": .object(["enabled": .bool(true)]),
                ]),
                "otherSetting": .string("value"),
            ],
            "openai": ["logit_bias": .object(["50256": .number(-100)])],
        ])
    }

    @Test("merges a JSON response format field by field")
    func responseFormatMerge() async throws {
        let result = try await transform(
            DefaultSettings(responseFormat: .json(
                schema: .object(["type": .string("object")]),
                name: "answer",
                description: nil
            )),
            LanguageModelV4CallOptions(
                prompt: middlewareTestPrompt,
                responseFormat: .json(schema: nil, name: nil, description: "The answer")
            )
        )

        #expect(result.responseFormat == .json(
            schema: .object(["type": .string("object")]),
            name: "answer",
            description: "The answer"
        ))
    }

    @Test("applies defaults on the V4 path")
    func v3() async throws {
        let middleware: LanguageModelV4Middleware = defaultSettingsMiddleware(settings: DefaultSettings(
            temperature: 0.7,
            providerOptions: ["openai": ["nested": .object(["a": .bool(true)])]]
        ))
        let result = try await middleware.transformParams!(
            .generate,
            LanguageModelV4CallOptions(
                prompt: [.user(content: [.text(LanguageModelV4TextPart(text: "Hello"))], providerOptions: nil)],
                providerOptions: ["openai": ["nested": .object(["b": .bool(true)])]]
            ),
            MockLanguageModelV4()
        )

        #expect(result.temperature == 0.7)
        #expect(result.providerOptions == ["openai": ["nested": .object(["a": .bool(true), "b": .bool(true)])]])
    }
}

/**
 Tests for DefaultSettingsMiddleware.

 Port of `@ai-sdk/ai/src/middleware/default-settings-middleware.test.ts`.
 */

import Testing
import Foundation
@testable import SwiftAISDK

@Suite("DefaultSettingsMiddleware Tests")
struct DefaultSettingsMiddlewareTests {

    // MARK: - Helper Constants

    static let baseParams = LanguageModelV3CallOptions(
        prompt: [
            .user(
                content: [
                    .text(LanguageModelV3TextPart(text: "Hello, world!"))
                ],
                providerOptions: nil
            )
        ]
    )

    static let mockModel = MockLanguageModelV3()

    // MARK: - transformParams Tests

    @Test("should apply default settings")
    func testApplyDefaultSettings() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(temperature: 0.7)
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.temperature == 0.7)
    }

    @Test("should give precedence to user-provided settings")
    func testUserProvidedSettingsPrecedence() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(temperature: 0.7)
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            temperature: 0.5
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.temperature == 0.5)
    }

    @Test("should merge provider metadata with default settings")
    func testMergeProviderMetadata() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                temperature: 0.7,
                providerOptions: [
                    "anthropic": [
                        "cacheControl": .object(["type": .string("ephemeral")])
                    ]
                ]
            )
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.temperature == 0.7)
        #expect(result.providerOptions?["anthropic"] != nil)

        if let anthropic = result.providerOptions?["anthropic"],
           let cacheControl = anthropic["cacheControl"],
           case .object(let obj) = cacheControl,
           case .string(let type) = obj["type"] {
            #expect(type == "ephemeral")
        }
    }

    @Test("should merge complex provider metadata objects")
    func testMergeComplexProviderMetadata() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                providerOptions: [
                    "anthropic": [
                        "cacheControl": .object(["type": .string("ephemeral")]),
                        "feature": .object(["enabled": .bool(true)])
                    ],
                    "openai": [
                        "logit_bias": .object(["50256": .number(-100)])
                    ]
                ]
            )
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            providerOptions: [
                "anthropic": [
                    "feature": .object(["enabled": .bool(false)]),
                    "otherSetting": .string("value")
                ]
            ]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.providerOptions?["anthropic"] != nil)
        #expect(result.providerOptions?["openai"] != nil)

        if let anthropic = result.providerOptions?["anthropic"] {
            // cacheControl from defaults
            if case .object(let cacheControl) = anthropic["cacheControl"],
               case .string(let type) = cacheControl["type"] {
                #expect(type == "ephemeral")
            }
            // feature overridden by params
            if case .object(let feature) = anthropic["feature"],
               case .bool(let enabled) = feature["enabled"] {
                #expect(enabled == false)
            }
            // otherSetting from params
            if case .string(let value) = anthropic["otherSetting"] {
                #expect(value == "value")
            }
        }

        if let openai = result.providerOptions?["openai"],
           case .object(let logitBias) = openai["logit_bias"],
           case .number(let value) = logitBias["50256"] {
            #expect(value == -100)
        }
    }

    @Test("should handle nested provider metadata objects correctly")
    func testNestedProviderMetadata() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                providerOptions: [
                    "anthropic": [
                        "tools": .object([
                            "retrieval": .object(["enabled": .bool(true)]),
                            "math": .object(["enabled": .bool(true)])
                        ])
                    ]
                ]
            )
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            providerOptions: [
                "anthropic": [
                    "tools": .object([
                        "retrieval": .object(["enabled": .bool(false)]),
                        "code": .object(["enabled": .bool(true)])
                    ])
                ]
            ]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.providerOptions?["anthropic"] != nil)

        if let anthropic = result.providerOptions?["anthropic"],
           case .object(let tools) = anthropic["tools"] {
            // retrieval overridden
            if case .object(let retrieval) = tools["retrieval"],
               case .bool(let enabled) = retrieval["enabled"] {
                #expect(enabled == false)
            }
            // math from defaults
            if case .object(let math) = tools["math"],
               case .bool(let enabled) = math["enabled"] {
                #expect(enabled == true)
            }
            // code from params
            if case .object(let code) = tools["code"],
               case .bool(let enabled) = code["enabled"] {
                #expect(enabled == true)
            }
        }
    }

    // MARK: - Temperature Tests

    @Test("should keep 0 if settings.temperature is not set")
    func testKeepZeroTemperature() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings()
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            temperature: 0
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.temperature == 0)
    }

    @Test("should use default temperature if param temperature is undefined")
    func testDefaultTemperatureWhenUndefined() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(temperature: 0.7)
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.temperature == 0.7)
    }

    @Test("should not use default temperature if param temperature is null")
    func testExplicitNullTemperature() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(temperature: 0.7)
        )

        // In Swift, we test the dictionary-level null handling
        // TypeScript: temperature: null as any
        // Swift: temperature key exists in dictionary with NSNull value
        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            temperature: nil  // Start with nil
        )

        // Convert to dictionary and inject NSNull to simulate "explicitly null"
        var paramsDict = params.toDictionary()
        paramsDict["temperature"] = NSNull()  // Explicit null, not undefined

        let settingsDict = DefaultSettings(temperature: 0.7).toDictionary()

        // Merge - explicit null should override default
        guard let merged = mergeObjects(settingsDict, paramsDict) else {
            Issue.record("mergeObjects returned nil unexpectedly")
            return
        }

        // Verify NSNull is preserved in merged dictionary
        #expect(merged["temperature"] is NSNull)

        // Convert back to CallOptions
        let result = LanguageModelV3CallOptions.fromDictionary(merged)

        // In Swift: NSNull in dictionary becomes nil in optional
        // This matches TypeScript behavior where null !== undefined
        // Result should be nil (not 0.7), indicating "explicitly no temperature"
        #expect(result.temperature == nil)
    }

    @Test("should use param temperature by default")
    func testParamTemperaturePrecedence() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(temperature: 0.7)
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            temperature: 0.9
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.temperature == 0.9)
    }

    // MARK: - Other Settings Tests

    @Test("should apply default maxOutputTokens")
    func testDefaultMaxOutputTokens() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(maxOutputTokens: 100)
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.maxOutputTokens == 100)
    }

    @Test("should prioritize param maxOutputTokens")
    func testParamMaxOutputTokensPrecedence() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(maxOutputTokens: 100)
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            maxOutputTokens: 50
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.maxOutputTokens == 50)
    }

    @Test("should apply default stopSequences")
    func testDefaultStopSequences() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(stopSequences: ["stop"])
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.stopSequences == ["stop"])
    }

    @Test("should prioritize param stopSequences")
    func testParamStopSequencesPrecedence() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(stopSequences: ["stop"])
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            stopSequences: ["end"]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.stopSequences == ["end"])
    }

    @Test("should apply default topP")
    func testDefaultTopP() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(topP: 0.9)
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.topP == 0.9)
    }

    @Test("should prioritize param topP")
    func testParamTopPPrecedence() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(topP: 0.9)
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            topP: 0.5
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.topP == 0.5)
    }

    // MARK: - Headers Tests

    @Test("should merge headers")
    func testMergeHeaders() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                headers: [
                    "X-Custom-Header": "test",
                    "X-Another-Header": "test2"
                ]
            )
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            headers: ["X-Custom-Header": "test2"]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.headers?["X-Custom-Header"] == "test2")
        #expect(result.headers?["X-Another-Header"] == "test2")
    }

    @Test("should handle empty default headers")
    func testEmptyDefaultHeaders() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(headers: [:])
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            headers: ["X-Param-Header": "param"]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.headers?["X-Param-Header"] == "param")
    }

    @Test("should handle empty param headers")
    func testEmptyParamHeaders() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                headers: ["X-Default-Header": "default"]
            )
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            headers: [:]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.headers?["X-Default-Header"] == "default")
    }

    @Test("should handle both headers being undefined")
    func testUndefinedHeaders() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings()
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.headers == nil)
    }

    // MARK: - ProviderOptions Tests

    @Test("should handle empty default providerOptions")
    func testEmptyDefaultProviderOptions() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                providerOptions: [:]
            )
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            providerOptions: [
                "openai": ["user": .string("param-user")]
            ]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.providerOptions?["openai"] != nil)
        if let openai = result.providerOptions?["openai"],
           case .string(let user) = openai["user"] {
            #expect(user == "param-user")
        }
    }

    @Test("should handle empty param providerOptions")
    func testEmptyParamProviderOptions() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings(
                providerOptions: [
                    "anthropic": ["user": .string("default-user")]
                ]
            )
        )

        let params = LanguageModelV3CallOptions(
            prompt: Self.baseParams.prompt,
            providerOptions: [:]
        )

        let result = try await middleware.transformParams!(
            .generate,
            params,
            Self.mockModel
        )

        #expect(result.providerOptions?["anthropic"] != nil)
        if let anthropic = result.providerOptions?["anthropic"],
           case .string(let user) = anthropic["user"] {
            #expect(user == "default-user")
        }
    }

    @Test("should handle both providerOptions being undefined")
    func testUndefinedProviderOptions() async throws {
        let middleware = defaultSettingsMiddleware(
            settings: DefaultSettings()
        )

        let result = try await middleware.transformParams!(
            .generate,
            Self.baseParams,
            Self.mockModel
        )

        #expect(result.providerOptions == nil)
    }
}

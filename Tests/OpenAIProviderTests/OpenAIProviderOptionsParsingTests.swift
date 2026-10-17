import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAIProviderOptionsParsing")
struct OpenAIProviderOptionsParsingTests {
    @Test("chat options reject null logprobs")
    func chatOptionsRejectNullLogprobs() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "logprobs": .null
            ]
        ]

        do {
            let _: OpenAIChatLanguageModelOptions? = try await parseProviderOptions(
                provider: "openai",
                providerOptions: providerOptions,
                schema: openAIChatProviderOptionsSchema
            )
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid openai provider options")
            guard let typeError = error.cause as? TypeValidationError else {
                Issue.record("Expected TypeValidationError as cause")
                return
            }
            guard let schemaError = typeError.cause as? SchemaValidationIssuesError else {
                Issue.record("Expected SchemaValidationIssuesError as TypeValidationError cause")
                return
            }
            #expect(schemaError.vendor == "openai")
            #expect(
                String(describing: schemaError.issues).contains("logprobs must be boolean or number"),
                "Expected logprobs null validation issue"
            )
        }
    }

    @Test("chat options parse GPT-5.6 max effort and prompt cache options")
    func chatOptionsParseMaxEffortAndPromptCacheOptions() async throws {
        let parsed: OpenAIChatLanguageModelOptions? = try await parseProviderOptions(
            provider: "openai",
            providerOptions: [
                "openai": [
                    "reasoningEffort": .string("max"),
                    "promptCacheOptions": .object([
                        "mode": .string("explicit"),
                        "ttl": .string("30m")
                    ])
                ]
            ],
            schema: openAIChatProviderOptionsSchema
        )

        #expect(parsed?.reasoningEffort == .max)
        #expect(parsed?.promptCacheOptions == .init(mode: .explicit, ttl: .thirtyMinutes))
    }

    @Test("completion options allow fractional logprobs")
    func completionOptionsAllowFractionalLogprobs() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "logprobs": .number(1.5)
            ]
        ]

        let parsed: OpenAILanguageModelCompletionOptions? = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openAICompletionProviderOptionsSchema
        )

        guard let parsed else {
            Issue.record("Expected parsed completion provider options")
            return
        }

        guard case .number(let value)? = parsed.logprobs else {
            Issue.record("Expected numeric logprobs option")
            return
        }

        #expect(value == 1.5)
    }

    @Test("completion options reject null logprobs")
    func completionOptionsRejectNullLogprobs() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "logprobs": .null
            ]
        ]

        do {
            let _: OpenAILanguageModelCompletionOptions? = try await parseProviderOptions(
                provider: "openai",
                providerOptions: providerOptions,
                schema: openAICompletionProviderOptionsSchema
            )
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid openai provider options")
            guard let typeError = error.cause as? TypeValidationError else {
                Issue.record("Expected TypeValidationError as cause")
                return
            }
            guard let schemaError = typeError.cause as? SchemaValidationIssuesError else {
                Issue.record("Expected SchemaValidationIssuesError as TypeValidationError cause")
                return
            }
            #expect(schemaError.vendor == "openai")
            #expect(
                String(describing: schemaError.issues).contains("logprobs must be boolean or number"),
                "Expected logprobs null validation issue"
            )
        }
    }

    @Test("embedding options allow fractional dimensions")
    func embeddingOptionsAllowFractionalDimensions() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "dimensions": .number(1536.5)
            ]
        ]

        let parsed: OpenAIEmbeddingModelOptions? = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openaiEmbeddingProviderOptionsSchema
        )

        #expect(parsed?.dimensions == 1536.5)
    }

    @Test("embedding options reject null dimensions")
    func embeddingOptionsRejectNullDimensions() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "dimensions": .null
            ]
        ]

        do {
            let _: OpenAIEmbeddingModelOptions? = try await parseProviderOptions(
                provider: "openai",
                providerOptions: providerOptions,
                schema: openaiEmbeddingProviderOptionsSchema
            )
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid openai provider options")
            guard let typeError = error.cause as? TypeValidationError else {
                Issue.record("Expected TypeValidationError as cause")
                return
            }
            guard let schemaError = typeError.cause as? SchemaValidationIssuesError else {
                Issue.record("Expected SchemaValidationIssuesError as TypeValidationError cause")
                return
            }
            #expect(schemaError.vendor == "openai")
            #expect(
                String(describing: schemaError.issues).contains("dimensions must be a number"),
                "Expected dimensions null validation issue"
            )
        }
    }

    @Test("image generation options reject fractional outputCompression")
    func imageGenerationOptionsRejectFractionalOutputCompression() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "outputCompression": .number(80.5)
            ]
        ]

        do {
            let _: OpenAIImageModelGenerationOptions? = try await parseProviderOptions(
                provider: "openai",
                providerOptions: providerOptions,
                schema: openAIImageModelGenerationOptionsSchema
            )
            Issue.record("Expected InvalidArgumentError")
        } catch let error as InvalidArgumentError {
            #expect(error.argument == "providerOptions")
            #expect(error.message == "invalid openai provider options")
            guard let typeError = error.cause as? TypeValidationError else {
                Issue.record("Expected TypeValidationError as cause")
                return
            }
            guard let schemaError = typeError.cause as? SchemaValidationIssuesError else {
                Issue.record("Expected SchemaValidationIssuesError as TypeValidationError cause")
                return
            }
            #expect(schemaError.vendor == "openai")
            #expect(
                String(describing: schemaError.issues).contains("outputCompression must be an integer"),
                "Expected outputCompression integer validation issue"
            )
        }
    }

}

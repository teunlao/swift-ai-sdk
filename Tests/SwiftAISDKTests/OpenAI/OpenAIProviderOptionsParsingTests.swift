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
            let _: OpenAIChatProviderOptions? = try await parseProviderOptions(
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

    @Test("completion options allow fractional logprobs")
    func completionOptionsAllowFractionalLogprobs() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "logprobs": .number(1.5)
            ]
        ]

        let parsed: OpenAICompletionProviderOptions? = try await parseProviderOptions(
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
            let _: OpenAICompletionProviderOptions? = try await parseProviderOptions(
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

        let parsed: OpenAIEmbeddingProviderOptions? = try await parseProviderOptions(
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
            let _: OpenAIEmbeddingProviderOptions? = try await parseProviderOptions(
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

    @Test("responses options allow fractional maxToolCalls")
    func responsesOptionsAllowFractionalMaxToolCalls() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "maxToolCalls": .number(3.5)
            ]
        ]

        let parsed: OpenAIResponsesProviderOptions? = try await parseProviderOptions(
            provider: "openai",
            providerOptions: providerOptions,
            schema: openAIResponsesProviderOptionsSchema
        )

        #expect(parsed?.maxToolCalls == 3.5)
    }

    @Test("responses options reject null systemMessageMode")
    func responsesOptionsRejectNullSystemMessageMode() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "systemMessageMode": .null
            ]
        ]

        do {
            let _: OpenAIResponsesProviderOptions? = try await parseProviderOptions(
                provider: "openai",
                providerOptions: providerOptions,
                schema: openAIResponsesProviderOptionsSchema
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
                String(describing: schemaError.issues).contains("systemMessageMode must be a string"),
                "Expected systemMessageMode null validation issue"
            )
        }
    }

    @Test("responses options reject null logprobs")
    func responsesOptionsRejectNullLogprobs() async throws {
        let providerOptions: SharedV3ProviderOptions = [
            "openai": [
                "logprobs": .null
            ]
        ]

        do {
            let _: OpenAIResponsesProviderOptions? = try await parseProviderOptions(
                provider: "openai",
                providerOptions: providerOptions,
                schema: openAIResponsesProviderOptionsSchema
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
}

/**
 Tests for structured output parsing helpers.

 Port of `@ai-sdk/ai/src/generate-text/output.test.ts`.
 */

import Testing
import Foundation
@testable import SwiftAISDK
import AISDKProvider
import AISDKProviderUtils

@Suite("Output.object Tests")
struct OutputTests {
    private struct TestOutput: Codable, Equatable, Sendable {
        let content: String
    }

    private let schema: FlexibleSchema<TestOutput> = FlexibleSchema(
        Schema(
            jsonSchemaResolver: {
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "content": .object([
                            "type": .string("string")
                        ])
                    ]),
                    "required": .array([.string("content")]),
                    "additionalProperties": .bool(false)
                ])
            },
            validator: { value in
                do {
                    let data: Data

                    if let jsonValue = value as? JSONValue {
                        data = try JSONEncoder().encode(jsonValue)
                    } else if JSONSerialization.isValidJSONObject(value) {
                        data = try JSONSerialization.data(withJSONObject: value, options: [])
                    } else {
                        throw SchemaJSONSerializationError(value: value)
                    }

                    let decoded = try JSONDecoder().decode(TestOutput.self, from: data)
                    return .success(value: decoded)
                } catch let error as SchemaJSONSerializationError {
                    let wrapped = TypeValidationError.wrap(value: value, cause: error)
                    return .failure(error: wrapped)
                } catch {
                    let wrapped = TypeValidationError.wrap(value: value, cause: error)
                    return .failure(error: wrapped)
                }
            }
        )
    )

    private let context = Output.Context(
        response: LanguageModelResponseMetadata(
            id: "123",
            timestamp: Date(timeIntervalSince1970: 0),
            modelId: "456"
        ),
        usage: LanguageModelUsage(
            inputTokens: 1,
            outputTokens: 2,
            totalTokens: 3,
            reasoningTokens: nil,
            cachedInputTokens: nil
        ),
        finishReason: .length
    )

    private func makeOutput() -> Output.Specification<TestOutput, JSONValue> {
        Output.object(schema: schema)
    }

    @Test("should parse the output of the model")
    func parsesSuccessfulOutput() async throws {
        let output = makeOutput()
        let result = try await output.parseOutput(
            text: "{ \"content\": \"test\" }",
            context: context
        )

        #expect(result == TestOutput(content: "test"))
    }

    @Test("should throw NoObjectGeneratedError when parsing fails")
    func throwsWhenParsingFails() async throws {
        let output = makeOutput()
        do {
            _ = try await output.parseOutput(
                text: "{ broken json",
                context: context
            )
            Issue.record("Expected parseOutput to throw")
        } catch {
            verifyNoObjectGeneratedError(
                error,
                expected: ExpectedNoObjectGeneratedError(
                    message: "No object generated: could not parse the response.",
                    response: context.response,
                    usage: context.usage,
                    finishReason: context.finishReason
                )
            )
        }
    }

    @Test("should throw NoObjectGeneratedError when schema validation fails")
    func throwsWhenSchemaValidationFails() async throws {
        let output = makeOutput()
        do {
            _ = try await output.parseOutput(
                text: "{ \"content\": 123 }",
                context: context
            )
            Issue.record("Expected parseOutput to throw")
        } catch {
            verifyNoObjectGeneratedError(
                error,
                expected: ExpectedNoObjectGeneratedError(
                    message: "No object generated: response did not match schema.",
                    response: context.response,
                    usage: context.usage,
                    finishReason: context.finishReason
                )
            )
        }
    }

    @Test("convenience overload infers schema from Codable type")
    func convenienceOverloadInfersSchema() async throws {
        let spec = Output.object(TestOutput.self, name: "codable_output")
        let format = try await spec.responseFormat()

        guard case let .json(schema?, name?, description) = format else {
            Issue.record("Expected json response format")
            return
        }

        #expect(name == "codable_output")
        #expect(description == nil)
        #expect(schema != nil)
    }
}

/**
 Output parser for text and object generation.

 Port of `@ai-sdk/ai/src/generate-text/output.ts`.

 Provides two output modes:
 - `text()`: Parse text output
 - `object(schema:)`: Parse and validate structured JSON output against a schema

 The Output protocol handles both partial parsing (for streaming) and final
 output parsing with validation.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Output parser protocol for text and object generation
public protocol Output: Sendable {
    /// Output type identifier
    var type: String { get }

    /// Response format configuration for the language model
    func responseFormat() async throws -> LanguageModelV3ResponseFormat

    /// Parse partial output (for streaming)
    /// - Parameter text: The partial text to parse
    /// - Returns: Parsed partial result, or nil if parsing not yet possible
    func parsePartial(text: String) async throws -> JSONValue?

    /// Parse final output with validation
    /// - Parameters:
    ///   - text: The complete text to parse
    ///   - response: Response metadata
    ///   - usage: Token usage information
    ///   - finishReason: Reason why generation finished
    /// - Returns: Parsed and validated output
    func parseOutput(
        text: String,
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason
    ) async throws -> JSONValue
}

// MARK: - Text Output

/// Creates a text output parser
/// - Returns: Output parser that returns text as-is
public func text() -> any Output {
    TextOutput()
}

private struct TextOutput: Output {
    public var type: String { "text" }

    public func responseFormat() async throws -> LanguageModelV3ResponseFormat {
        return .text
    }

    public func parsePartial(text: String) async throws -> JSONValue? {
        .string(text)
    }

    public func parseOutput(
        text: String,
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason
    ) async throws -> JSONValue {
        .string(text)
    }
}

// MARK: - Object Output

/// Creates an object output parser with schema validation
/// - Parameter schema: Schema to validate output against (using type erasure)
/// - Returns: Output parser that validates JSON objects
public func object<T>(schema: Schema<T>) -> any Output {
    ObjectOutput(schema: schema)
}

private struct ObjectOutput<T>: Output {
    let schema: Schema<T>

    public var type: String { "object" }

    public func responseFormat() async throws -> LanguageModelV3ResponseFormat {
        let jsonSchema = try await schema.jsonSchema()
        return .json(schema: jsonSchema, name: nil, description: nil)
    }

    public func parsePartial(text: String) async throws -> JSONValue? {
        let result = await parsePartialJson(text)

        switch result.state {
        case .failedParse, .undefinedInput:
            return nil

        case .repairedParse, .successfulParse:
            // Note: currently no validation of partial results
            return result.value
        }
    }

    public func parseOutput(
        text: String,
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason
    ) async throws -> JSONValue {
        // Parse JSON
        let parseResult = await safeParseJSON(ParseJSONOptions(text: text))

        let value: JSONValue
        switch parseResult {
        case .success(let parsedValue, _):
            value = parsedValue
        case .failure(let error, _):
            throw NoObjectGeneratedError(
                message: "No object generated: could not parse the response.",
                cause: error,
                text: text,
                response: response,
                usage: usage,
                finishReason: finishReason
            )
        }

        // Validate against schema
        let validationResult = await safeValidateTypes(
            ValidateTypesOptions(value: value, schema: FlexibleSchema(schema))
        )

        switch validationResult {
        case .success:
            // Return the original JSONValue (validation passed)
            return value
        case .failure(let error, _):
            throw NoObjectGeneratedError(
                message: "No object generated: response did not match schema.",
                cause: error,
                text: text,
                response: response,
                usage: usage,
                finishReason: finishReason
            )
        }
    }
}

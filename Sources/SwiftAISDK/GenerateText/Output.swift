import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Output parser helpers for text and object generation.

 Port of `@ai-sdk/ai/src/generate-text/output.ts`.

 Provides factory helpers (`Output.text()`, `Output.object(schema:)`) that return
 typed specifications for parsing structured or plain-text model outputs. These
 specifications are consumed by `generateText`/`streamText` to configure model
 response formats and to decode the final results.
 */
public enum Output {
    // MARK: - Types

    /// Output kind identifier (matches upstream string union `'text' | 'object'`).
    public enum OutputType: String, Sendable {
        case text
        case object
    }

    /// Context information available when parsing the final output.
    public struct Context: Sendable {
        public let response: LanguageModelResponseMetadata
        public let usage: LanguageModelUsage
        public let finishReason: FinishReason

        public init(
            response: LanguageModelResponseMetadata,
            usage: LanguageModelUsage,
            finishReason: FinishReason
        ) {
            self.response = response
            self.usage = usage
            self.finishReason = finishReason
        }
    }

    /**
     Type-erased specification describing how to request and parse model output.

     - `OutputValue`: Final structured type produced when parsing completes.
     - `PartialOutput`: Partial result type emitted during streaming (unused for `generateText` but required for parity with upstream API).
     */
    public struct Specification<OutputValue: Sendable, PartialOutput: Sendable>: Sendable {
        public let type: OutputType

        private let responseFormatClosure: @Sendable () async throws -> LanguageModelV3ResponseFormat
        private let parsePartialClosure: @Sendable (_ text: String) async throws -> PartialOutput?
        private let parseOutputClosure: @Sendable (_ text: String, _ context: Context) async throws -> OutputValue

        public init(
            type: OutputType,
            responseFormat: @escaping @Sendable () async throws -> LanguageModelV3ResponseFormat,
            parsePartial: @escaping @Sendable (_ text: String) async throws -> PartialOutput?,
            parseOutput: @escaping @Sendable (_ text: String, _ context: Context) async throws -> OutputValue
        ) {
            self.type = type
            self.responseFormatClosure = responseFormat
            self.parsePartialClosure = parsePartial
            self.parseOutputClosure = parseOutput
        }

        /// Resolve the language-model response format for this output.
        public func responseFormat() async throws -> LanguageModelV3ResponseFormat {
            try await responseFormatClosure()
        }

        /// Parse a partial output chunk (used by streaming flows).
        public func parsePartial(text: String) async throws -> PartialOutput? {
            try await parsePartialClosure(text)
        }

        /// Parse the final output using explicit context values.
        public func parseOutput(
            text: String,
            context: Context
        ) async throws -> OutputValue {
            try await parseOutputClosure(text, context)
        }

        /// Convenience overload that mirrors the upstream call-site signature.
        public func parseOutput(
            text: String,
            response: LanguageModelResponseMetadata,
            usage: LanguageModelUsage,
            finishReason: FinishReason
        ) async throws -> OutputValue {
            try await parseOutput(
                text: text,
                context: Context(
                    response: response,
                    usage: usage,
                    finishReason: finishReason
                )
            )
        }
    }

    // MARK: - Text Output

    /// Create a specification that treats the model output as plain text.
    public static func text() -> Specification<String, String> {
        Specification<String, String>(
            type: .text,
            responseFormat: { .text },
            parsePartial: { text in text },
            parseOutput: { text, _ in text }
        )
    }

    // MARK: - Object Output

    /// Create a specification that parses the output as JSON validated against a schema.
    ///
    /// - Parameter schema: Schema describing the expected output structure.
    public static func object<OutputValue: Sendable>(
        schema inputSchema: FlexibleSchema<OutputValue>,
        name: String? = nil,
        description: String? = nil
    ) -> Specification<OutputValue, JSONValue> {
        let resolvedSchema = inputSchema.resolve()

        return Specification<OutputValue, JSONValue>(
            type: .object,
            responseFormat: {
                let jsonSchema = try await resolvedSchema.jsonSchema()
                return .json(schema: jsonSchema, name: name, description: description)
            },
            parsePartial: { text in
                let result = await parsePartialJson(text)

                switch result.state {
                case .failedParse, .undefinedInput:
                    return nil
                case .repairedParse, .successfulParse:
                    // Note: currently no validation of partial results.
                    return result.value
                }
            },
            parseOutput: { text, context in
                let parseResult = await safeParseJSON(ParseJSONOptions(text: text))

                let parsedValue: JSONValue
                switch parseResult {
                case .success(let value, _):
                    parsedValue = value
                case .failure(let error, _):
                    throw NoObjectGeneratedError(
                        message: "No object generated: could not parse the response.",
                        cause: error,
                        text: text,
                        response: context.response,
                        usage: context.usage,
                        finishReason: context.finishReason
                    )
                }

                let validationResult = await safeValidateTypes(
                    ValidateTypesOptions(
                        value: parsedValue,
                        schema: FlexibleSchema(resolvedSchema)
                    )
                )

                switch validationResult {
                case .success(let typedValue, _):
                    return typedValue
                case .failure(let error, _):
                    throw NoObjectGeneratedError(
                        message: "No object generated: response did not match schema.",
                        cause: error,
                        text: text,
                        response: context.response,
                        usage: context.usage,
                        finishReason: context.finishReason
                    )
                }
            }
        )
    }

    /// Convenience overload that accepts a plain `Schema` instead of a `FlexibleSchema`.
    public static func object<OutputValue: Sendable>(
        schema inputSchema: Schema<OutputValue>,
        name: String? = nil,
        description: String? = nil
    ) -> Specification<OutputValue, JSONValue> {
        object(schema: FlexibleSchema(inputSchema), name: name, description: description)
    }

    /// Convenience overload that automatically derives the schema from a Codable type.
    public static func object<OutputValue: Codable & Sendable>(
        _ type: OutputValue.Type,
        name: String? = nil,
        description: String? = nil
    ) -> Specification<OutputValue, JSONValue> {
        object(schema: FlexibleSchema.auto(type), name: name, description: description)
    }
}

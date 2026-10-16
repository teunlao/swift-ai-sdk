import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Output specifications for `generateText` / `streamText`.

 Port of `@ai-sdk/ai/src/generate-text/output.ts`: `text()`, `object()`,
 `array()`, `choice()` and `json()`.
 */
public enum Output {
    /// Context available when parsing the final output.
    public struct Context: Sendable {
        public let response: LanguageModelResponseMetadata
        public let usage: LanguageModelUsage
        public let finishReason: FinishReason

        public init(response: LanguageModelResponseMetadata, usage: LanguageModelUsage, finishReason: FinishReason) {
            self.response = response
            self.usage = usage
            self.finishReason = finishReason
        }
    }

    /**
     How to request and parse model output.

     - `OutputValue`: the parsed final output.
     - `PartialOutput`: the partial output emitted while streaming.
     */
    public struct Specification<OutputValue: Sendable, PartialOutput: Sendable>: OutputSpecification {
        /// Output kind (`text`, `object`, `array`, `choice`, `json`).
        public let name: String

        private let responseFormatClosure: @Sendable () async throws -> LanguageModelV4ResponseFormat
        private let parsePartialClosure: @Sendable (_ text: String) async throws -> PartialOutput?
        private let parseOutputClosure: @Sendable (_ text: String, _ context: Context) async throws -> OutputValue
        /// Elements newly completed in a partial output, given the number already published.
        let newElements: (@Sendable (_ partial: PartialOutput, _ published: Int) throws -> [JSONValue])?

        public init(
            name: String,
            responseFormat: @escaping @Sendable () async throws -> LanguageModelV4ResponseFormat,
            parsePartial: @escaping @Sendable (_ text: String) async throws -> PartialOutput?,
            parseOutput: @escaping @Sendable (_ text: String, _ context: Context) async throws -> OutputValue
        ) {
            self.init(
                name: name,
                responseFormat: responseFormat,
                parsePartial: parsePartial,
                parseOutput: parseOutput,
                newElements: nil
            )
        }

        init(
            name: String,
            responseFormat: @escaping @Sendable () async throws -> LanguageModelV4ResponseFormat,
            parsePartial: @escaping @Sendable (_ text: String) async throws -> PartialOutput?,
            parseOutput: @escaping @Sendable (_ text: String, _ context: Context) async throws -> OutputValue,
            newElements: (@Sendable (_ partial: PartialOutput, _ published: Int) throws -> [JSONValue])?
        ) {
            self.name = name
            self.responseFormatClosure = responseFormat
            self.parsePartialClosure = parsePartial
            self.parseOutputClosure = parseOutput
            self.newElements = newElements
        }

        /// The response format requested from the model.
        public func responseFormat() async throws -> LanguageModelV4ResponseFormat? {
            try await responseFormatClosure()
        }

        /// Parses partial output text while streaming; `nil` when nothing can be parsed yet.
        public func parsePartial(text: String) async throws -> PartialOutput? {
            try await parsePartialClosure(text)
        }

        /// Parses the final output text.
        public func parseOutput(text: String, context: Context) async throws -> OutputValue {
            try await parseOutputClosure(text, context)
        }

        public func parseOutput(
            text: String,
            response: LanguageModelResponseMetadata,
            usage: LanguageModelUsage,
            finishReason: FinishReason
        ) async throws -> OutputValue {
            try await parseOutput(
                text: text,
                context: Context(response: response, usage: usage, finishReason: finishReason)
            )
        }
    }

    // MARK: - text

    /// Plain text output.
    public static func text() -> Specification<String, String> {
        Specification(
            name: "text",
            responseFormat: { .text },
            parsePartial: { text in text },
            parseOutput: { text, _ in text }
        )
    }

    // MARK: - object

    /// JSON output validated against a schema.
    public static func object<OutputValue: Sendable>(
        schema inputSchema: FlexibleSchema<OutputValue>,
        name: String? = nil,
        description: String? = nil
    ) -> Specification<OutputValue, JSONValue> {
        let schema = inputSchema.resolve()

        return Specification(
            name: "object",
            responseFormat: {
                .json(schema: try await schema.jsonSchema(), name: name, description: description)
            },
            parsePartial: { text in
                let result = await parsePartialJson(text)
                switch result.state {
                case .failedParse, .undefinedInput:
                    return nil
                case .repairedParse, .successfulParse:
                    return result.value
                }
            },
            parseOutput: { text, context in
                let value = try await parseOutputJSON(text, context: context)
                switch await safeValidateTypes(
                    ValidateTypesOptions(value: jsonValueToFoundation(value), schema: FlexibleSchema(schema))
                ) {
                case .success(let typed, _):
                    return typed
                case .failure(let error, _):
                    throw noObjectGenerated(.schemaMismatch, cause: error, text: text, context: context)
                }
            }
        )
    }

    public static func object<OutputValue: Sendable>(
        schema inputSchema: Schema<OutputValue>,
        name: String? = nil,
        description: String? = nil
    ) -> Specification<OutputValue, JSONValue> {
        object(schema: FlexibleSchema(inputSchema), name: name, description: description)
    }

    /// Object output whose schema is derived from a `Codable` type.
    public static func object<OutputValue: Codable & Sendable>(
        _ type: OutputValue.Type,
        name: String? = nil,
        description: String? = nil
    ) -> Specification<OutputValue, JSONValue> {
        object(schema: FlexibleSchema.auto(type), name: name, description: description)
    }

    // MARK: - array

    /**
     Array output: the model returns `{ "elements": [...] }`; each element is
     validated against `element`.

     - Throws: `InvalidArgumentError` for negative or non-ordered bounds.
     */
    public static func array<Element: Sendable>(
        element inputElementSchema: FlexibleSchema<Element>,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        name: String? = nil,
        description: String? = nil
    ) throws -> Specification<[Element], [Element]> {
        try validateArrayBound("minItems", minItems)
        try validateArrayBound("maxItems", maxItems)
        if let minItems, let maxItems, minItems > maxItems {
            throw InvalidArgumentError(
                parameter: "minItems",
                value: .number(Double(minItems)),
                message: "minItems must be less than or equal to maxItems"
            )
        }

        let elementSchema = inputElementSchema.resolve()

        @Sendable func validateElement(_ value: JSONValue) async -> SafeValidateTypesResult<Element> {
            await safeValidateTypes(
                ValidateTypesOptions(value: jsonValueToFoundation(value), schema: FlexibleSchema(elementSchema))
            )
        }

        return Specification(
            name: "array",
            responseFormat: {
                var itemSchema: [String: JSONValue] = [:]
                if case .object(let object) = try await elementSchema.jsonSchema() {
                    itemSchema = object
                }
                let definitions = itemSchema.removeValue(forKey: "definitions")
                let defs = itemSchema.removeValue(forKey: "$defs")
                itemSchema.removeValue(forKey: "$schema")

                var elements: [String: JSONValue] = ["type": "array", "items": .object(itemSchema)]
                if let minItems { elements["minItems"] = .number(Double(minItems)) }
                if let maxItems { elements["maxItems"] = .number(Double(maxItems)) }

                var schema: [String: JSONValue] = [
                    "$schema": "http://json-schema.org/draft-07/schema#",
                    "type": "object",
                    "properties": .object(["elements": .object(elements)]),
                    "required": .array(["elements"]),
                    "additionalProperties": false,
                ]
                if let definitions { schema["definitions"] = definitions }
                if let defs { schema["$defs"] = defs }

                return .json(schema: .object(schema), name: name, description: description)
            },
            parsePartial: { text in
                let result = await parsePartialJson(text)
                switch result.state {
                case .failedParse, .undefinedInput:
                    return nil
                case .repairedParse, .successfulParse:
                    guard case .object(let outer)? = result.value, case .array(var rawElements)? = outer["elements"] else {
                        return nil
                    }
                    // The last element of a repaired parse may be incomplete.
                    if result.state == .repairedParse, !rawElements.isEmpty {
                        rawElements.removeLast()
                    }
                    var parsed: [Element] = []
                    for rawElement in rawElements {
                        if case .success(let value, _) = await validateElement(rawElement) {
                            parsed.append(value)
                        }
                    }
                    return parsed
                }
            },
            parseOutput: { text, context in
                let outerValue = try await parseOutputJSON(text, context: context)
                guard case .object(let outer) = outerValue, case .array(let rawElements)? = outer["elements"] else {
                    throw noObjectGenerated(
                        .schemaMismatch,
                        cause: TypeValidationError(
                            value: jsonValueToFoundation(outerValue),
                            cause: OutputValidationMessage("response must be an object with an elements array")
                        ),
                        text: text,
                        context: context
                    )
                }

                if let lengthError = arrayLengthValidationError(rawElements, minItems: minItems, maxItems: maxItems) {
                    throw noObjectGenerated(.schemaMismatch, cause: lengthError, text: text, context: context)
                }

                var validated: [Element] = []
                for rawElement in rawElements {
                    switch await validateElement(rawElement) {
                    case .success(let value, _):
                        validated.append(value)
                    case .failure(let error, _):
                        throw noObjectGenerated(.schemaMismatch, cause: error, text: text, context: context)
                    }
                }
                return validated
            },
            newElements: { partial, published in
                guard partial.count > published else { return [] }
                if let maxItems, partial.count > maxItems {
                    throw arrayLengthValidationError(partial.map { _ in JSONValue.null }, minItems: nil, maxItems: maxItems)!
                }
                return partial[published...].map { element in
                    if let json = element as? JSONValue { return json }
                    guard let data = try? JSONEncoder().encode(AnyEncodable(element)) else { return .null }
                    return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .null
                }
            }
        )
    }

    /// Array output whose element schema is derived from a `Codable` type.
    public static func array<Element: Codable & Sendable>(
        _ elementType: Element.Type,
        minItems: Int? = nil,
        maxItems: Int? = nil,
        name: String? = nil,
        description: String? = nil
    ) throws -> Specification<[Element], [Element]> {
        try array(
            element: FlexibleSchema.auto(elementType),
            minItems: minItems,
            maxItems: maxItems,
            name: name,
            description: description
        )
    }

    // MARK: - choice

    /// One of the given string options.
    public static func choice(
        options: [String],
        name: String? = nil,
        description: String? = nil
    ) -> Specification<String, String> {
        Specification(
            name: "choice",
            responseFormat: {
                .json(
                    schema: .object([
                        "$schema": "http://json-schema.org/draft-07/schema#",
                        "type": "object",
                        "properties": .object([
                            "result": .object(["type": "string", "enum": .array(options.map(JSONValue.string))]),
                        ]),
                        "required": .array(["result"]),
                        "additionalProperties": false,
                    ]),
                    name: name,
                    description: description
                )
            },
            parsePartial: { text in
                let result = await parsePartialJson(text)
                switch result.state {
                case .failedParse, .undefinedInput:
                    return nil
                case .repairedParse, .successfulParse:
                    guard case .object(let outer)? = result.value, case .string(let value)? = outer["result"] else {
                        return nil
                    }
                    let matches = options.filter { $0.hasPrefix(value) }
                    if result.state == .successfulParse {
                        return matches.contains(value) ? value : nil
                    }
                    return matches.count == 1 ? matches[0] : nil
                }
            },
            parseOutput: { text, context in
                let outerValue = try await parseOutputJSON(text, context: context)
                guard case .object(let outer) = outerValue,
                      case .string(let value)? = outer["result"],
                      options.contains(value) else {
                    throw noObjectGenerated(
                        .schemaMismatch,
                        cause: TypeValidationError(
                            value: jsonValueToFoundation(outerValue),
                            cause: OutputValidationMessage("response must be an object that contains a choice value.")
                        ),
                        text: text,
                        context: context
                    )
                }
                return value
            }
        )
    }

    // MARK: - json

    /// Any JSON value, without a schema.
    public static func json(name: String? = nil, description: String? = nil) -> Specification<JSONValue, JSONValue> {
        Specification(
            name: "json",
            responseFormat: { .json(schema: nil, name: name, description: description) },
            parsePartial: { text in
                let result = await parsePartialJson(text)
                switch result.state {
                case .failedParse, .undefinedInput:
                    return nil
                case .repairedParse, .successfulParse:
                    return result.value
                }
            },
            parseOutput: { text, context in
                try await parseOutputJSON(text, context: context)
            }
        )
    }

    // MARK: - Helpers

    private enum FailureKind {
        case parse
        case schemaMismatch
    }

    private static func noObjectGenerated(
        _ kind: FailureKind,
        cause: any Error,
        text: String,
        context: Context
    ) -> NoObjectGeneratedError {
        NoObjectGeneratedError(
            message: kind == .parse
                ? "No object generated: could not parse the response."
                : "No object generated: response did not match schema.",
            cause: cause,
            text: text,
            response: context.response,
            usage: context.usage,
            finishReason: context.finishReason
        )
    }

    private static func parseOutputJSON(_ text: String, context: Context) async throws -> JSONValue {
        switch await safeParseJSON(ParseJSONOptions(text: text)) {
        case .success(let value, _):
            return value
        case .failure(let error, _):
            throw noObjectGenerated(.parse, cause: error, text: text, context: context)
        }
    }

    private static func validateArrayBound(_ name: String, _ value: Int?) throws {
        guard let value, value < 0 else { return }
        throw InvalidArgumentError(
            parameter: name,
            value: .number(Double(value)),
            message: "\(name) must be greater than or equal to 0"
        )
    }

    private static func arrayLengthValidationError(
        _ value: [JSONValue],
        minItems: Int?,
        maxItems: Int?
    ) -> TypeValidationError? {
        if let minItems, value.count < minItems {
            return TypeValidationError(
                value: jsonValueToFoundation(.array(value)),
                cause: OutputValidationMessage("elements array must contain at least \(minItems) items")
            )
        }
        if let maxItems, value.count > maxItems {
            return TypeValidationError(
                value: jsonValueToFoundation(.array(value)),
                cause: OutputValidationMessage("elements array must contain at most \(maxItems) items")
            )
        }
        return nil
    }
}

private struct OutputValidationMessage: LocalizedError, CustomStringConvertible, Sendable {
    let description: String
    init(_ description: String) { self.description = description }
    var errorDescription: String? { description }
}

private struct AnyEncodable: Encodable {
    let value: Any
    init(_ value: Any) { self.value = value }
    func encode(to encoder: Encoder) throws {
        guard let encodable = value as? Encodable else {
            throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath, debugDescription: "Not encodable"))
        }
        try encodable.encode(to: encoder)
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GenerateObjectPartialValidationResult<Partial: Sendable>: Sendable {
    public let partial: Partial
    public let textDelta: String

    public init(partial: Partial, textDelta: String) {
        self.partial = partial
        self.textDelta = textDelta
    }
}

public struct GenerateObjectValidationContext: Sendable {
    public let text: String
    public let response: LanguageModelResponseMetadata
    public let usage: LanguageModelUsage
    public let finishReason: FinishReason

    public init(
        text: String,
        response: LanguageModelResponseMetadata,
        usage: LanguageModelUsage,
        finishReason: FinishReason
    ) {
        self.text = text
        self.response = response
        self.usage = usage
        self.finishReason = finishReason
    }
}

public struct GenerateObjectOutputStrategy<PartialValue: Sendable, ResultValue: Sendable, ElementStream>: Sendable {
    public let type: GenerateObjectOutputKind
    public let jsonSchema: @Sendable () async throws -> JSONValue?
    public let validatePartial: @Sendable (
        _ value: JSONValue,
        _ textDelta: String,
        _ isFirstDelta: Bool,
        _ isFinalDelta: Bool,
        _ latestObject: PartialValue?
    ) async -> Result<GenerateObjectPartialValidationResult<PartialValue>, Error>
    public let validateFinal: @Sendable (
        _ value: JSONValue?,
        _ context: GenerateObjectValidationContext
    ) async -> Result<ResultValue, Error>
    public let createElementStream: @Sendable (
        _ stream: AsyncIterableStream<ObjectStreamPart<PartialValue>>
    ) -> ElementStream

    public init(
        type: GenerateObjectOutputKind,
        jsonSchema: @escaping @Sendable () async throws -> JSONValue?,
        validatePartial: @escaping @Sendable (
            _ value: JSONValue,
            _ textDelta: String,
            _ isFirstDelta: Bool,
            _ isFinalDelta: Bool,
            _ latestObject: PartialValue?
        ) async -> Result<GenerateObjectPartialValidationResult<PartialValue>, Error>,
        validateFinal: @escaping @Sendable (
            _ value: JSONValue?,
            _ context: GenerateObjectValidationContext
        ) async -> Result<ResultValue, Error>,
        createElementStream: @escaping @Sendable (
            _ stream: AsyncIterableStream<ObjectStreamPart<PartialValue>>
        ) -> ElementStream
    ) {
        self.type = type
        self.jsonSchema = jsonSchema
        self.validatePartial = validatePartial
        self.validateFinal = validateFinal
        self.createElementStream = createElementStream
    }
}

public enum ObjectStreamPart<Partial: Sendable>: Sendable {
    case object(Partial)
    case textDelta(String)
    case error(AnySendableError)
    case finish(GenerateObjectStreamFinish)
}

public struct GenerateObjectStreamFinish: Sendable {
    public let finishReason: FinishReason
    public let usage: LanguageModelUsage
    public let response: LanguageModelResponseMetadata
    public let providerMetadata: ProviderMetadata?

    public init(
        finishReason: FinishReason,
        usage: LanguageModelUsage,
        response: LanguageModelResponseMetadata,
        providerMetadata: ProviderMetadata?
    ) {
        self.finishReason = finishReason
        self.usage = usage
        self.response = response
        self.providerMetadata = providerMetadata
    }
}

public func makeNoSchemaOutputStrategy() -> GenerateObjectOutputStrategy<JSONValue, JSONValue, Never> {
    GenerateObjectOutputStrategy(
        type: .noSchema,
        jsonSchema: { nil },
        validatePartial: { value, textDelta, _, _, _ in
            .success(GenerateObjectPartialValidationResult(partial: value, textDelta: textDelta))
        },
        validateFinal: { value, context in
            guard let value else {
                return .failure(
                    NoObjectGeneratedError(
                        message: "No object generated: response did not match schema.",
                        text: context.text,
                        response: context.response,
                        usage: context.usage,
                        finishReason: context.finishReason
                    )
                )
            }
            return .success(value)
        },
        createElementStream: { _ in
            fatalError("Element stream is not available for no-schema output")
        }
    )
}

public func makeObjectOutputStrategy<ObjectResult>(
    schema: FlexibleSchema<ObjectResult>
) -> GenerateObjectOutputStrategy<[String: JSONValue], ObjectResult, Never> {
    GenerateObjectOutputStrategy(
        type: .object,
        jsonSchema: {
            try await schema.resolve().jsonSchema()
        },
        validatePartial: { value, textDelta, _, _, _ in
            guard case let .object(object) = value else {
                return .failure(TypeValidationError(value: value, cause: ValidationMessageError("value must be an object")))
            }
            return .success(GenerateObjectPartialValidationResult(partial: object, textDelta: textDelta))
        },
        validateFinal: { value, _ in
            let raw = jsonValueToAny(value ?? .null)
            switch await safeValidateTypes(ValidateTypesOptions(value: raw, schema: schema)) {
            case .success(let typed, _):
                return .success(typed)
            case .failure(let error, _):
                return .failure(error)
            }
        },
        createElementStream: { _ in
            fatalError("Element stream is not available for object output")
        }
    )
}

public func makeArrayOutputStrategy<ElementResult>(
    schema: FlexibleSchema<ElementResult>
) -> GenerateObjectOutputStrategy<[ElementResult], [ElementResult], AsyncIterableStream<ElementResult>> {
    GenerateObjectOutputStrategy(
        type: .array,
        jsonSchema: {
            let itemSchema = try await schema.resolve().jsonSchema()
            return .object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "elements": .object([
                        "type": .string("array"),
                        "items": itemSchema
                    ])
                ]),
                "required": .array([.string("elements")]),
                "additionalProperties": .bool(false)
            ])
        },
        validatePartial: { value, _, isFirstDelta, isFinalDelta, latest in
            guard case let .object(object) = value,
                  case let .array(elementsJSON)? = object["elements"] else {
                return .failure(TypeValidationError(value: value, cause: ValidationMessageError("value must be an object that contains an array of elements")))
            }

            var parsed: [ElementResult] = []
            parsed.reserveCapacity(elementsJSON.count)

            for (index, elementJSON) in elementsJSON.enumerated() {
                let validation = await safeValidateTypes(
                    ValidateTypesOptions(value: jsonValueToAny(elementJSON), schema: schema)
                )

                switch validation {
                case .success(let element, _):
                    parsed.append(element)
                case .failure(let error, _) where index == elementsJSON.count - 1 && !isFinalDelta:
                    continue
                case .failure(let error, _):
                    return .failure(error)
                }
            }

            let publishedCount = latest?.count ?? 0
            var deltaText = ""

            if isFirstDelta {
                deltaText += "["
            }

            if publishedCount > 0 && parsed.count > publishedCount {
                deltaText += ","
            }

            if parsed.count > publishedCount {
                let newElements = elementsJSON.dropFirst(publishedCount)
                let payload = newElements.compactMap { stringifyJSON($0) }.joined(separator: ",")
                deltaText += payload
            }

            if isFinalDelta {
                deltaText += "]"
            }

            return .success(
                GenerateObjectPartialValidationResult(partial: parsed, textDelta: deltaText)
            )
        },
        validateFinal: { value, _ in
            guard case let .object(objectValue)? = value,
                  case let .array(elementValues)? = objectValue["elements"] else {
                return .failure(TypeValidationError(value: value ?? .null, cause: ValidationMessageError("value must be an object that contains an array of elements")))
            }

            var finalArray: [ElementResult] = []
            finalArray.reserveCapacity(elementValues.count)

            for elementJSON in elementValues {
                let validation = await safeValidateTypes(
                    ValidateTypesOptions(value: jsonValueToAny(elementJSON), schema: schema)
                )

                switch validation {
                case .success(let element, _):
                    finalArray.append(element)
                case .failure(let error, _):
                    return .failure(error)
                }
            }

            return .success(finalArray)
        },
        createElementStream: { original in
            createAsyncIterableStream(source: AsyncThrowingStream<ElementResult, Error> { continuation in
                Task {
                    var iterator = original.makeAsyncIterator()
                    var published = 0

                    do {
                        while let part = try await iterator.next() {
                            switch part {
                            case .object(let array):
                                while published < array.count {
                                    continuation.yield(array[published])
                                    published += 1
                                }
                            case .textDelta:
                                break
                            case .error(let error):
                                continuation.finish(throwing: error.underlying)
                                return
                            case .finish:
                                continuation.finish()
                                return
                            }
                        }
                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            })
        }
    )
}

public func makeEnumOutputStrategy(values: [String]) -> GenerateObjectOutputStrategy<String, String, Never> {
    GenerateObjectOutputStrategy(
        type: .enumeration,
        jsonSchema: {
            .object([
                "$schema": .string("http://json-schema.org/draft-07/schema#"),
                "type": .string("object"),
                "properties": .object([
                    "result": .object([
                        "type": .string("string"),
                        "enum": .array(values.map { JSONValue.string($0) })
                    ])
                ]),
                "required": .array([.string("result")]),
                "additionalProperties": .bool(false)
            ])
        },
        validatePartial: { value, textDelta, _, _, _ in
            guard case let .object(object) = value,
                  case let .string(result)? = object["result"] else {
                return .failure(TypeValidationError(value: value, cause: ValidationMessageError("value must be an object that contains a string in the \"result\" property.")))
            }

            let matches = values.filter { $0.hasPrefix(result) }
            guard !result.isEmpty, !matches.isEmpty else {
                return .failure(TypeValidationError(value: value, cause: ValidationMessageError("value must be a string in the enum")))
            }

            let partial = matches.count == 1 ? matches[0] : result
            return .success(GenerateObjectPartialValidationResult(partial: partial, textDelta: textDelta))
        },
        validateFinal: { value, _ in
            guard case let .object(objectValue)? = value,
                  case let .string(result)? = objectValue["result"] else {
                return .failure(TypeValidationError(value: value ?? .null, cause: ValidationMessageError("value must be an object that contains a string in the \"result\" property.")))
            }

            guard values.contains(result) else {
                return .failure(TypeValidationError(value: value ?? .null, cause: ValidationMessageError("value must be a string in the enum")))
            }

            return .success(result)
        },
        createElementStream: { _ in
            fatalError("Element stream is not available for enum output")
        }
    )
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .null:
        return NSNull()
    case .bool(let bool):
        return bool
    case .number(let number):
        return number
    case .string(let string):
        return string
    case .array(let array):
        return array.map { jsonValueToAny($0) }
    case .object(let object):
        return object.mapValues { jsonValueToAny($0) }
    }
}

private func stringifyJSON(_ value: JSONValue) -> String? {
    switch value {
    case .null:
        return "null"
    case .bool(let bool):
        return bool ? "true" : "false"
    case .number(let number):
        return number.isFinite ? trimTrailingZeros(number) : String(number)
    case .string(let string):
        guard let data = try? JSONSerialization.data(withJSONObject: [string], options: []) else {
            return nil
        }
        guard let arrayEncoded = String(data: data, encoding: .utf8) else {
            return nil
        }
        let start = arrayEncoded.index(after: arrayEncoded.startIndex)
        let end = arrayEncoded.index(before: arrayEncoded.endIndex)
        return String(arrayEncoded[start..<end])
    case .array, .object:
        let anyValue = jsonValueToAny(value)
        guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: []) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private func trimTrailingZeros(_ number: Double) -> String {
    if number.rounded(.towardZero) == number {
        return String(Int(number))
    }
    return String(number)
}


private struct ValidationMessageError: Error, CustomStringConvertible, Sendable {
    let message: String
    init(_ message: String) { self.message = message }
    var description: String { message }
}

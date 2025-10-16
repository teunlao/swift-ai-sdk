import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Validates combinations of generate-object options.

 Port of `@ai-sdk/ai/src/generate-object/validate-object-generation-input.ts`.
 */
public func validateObjectGenerationInput(
    output: GenerateObjectOutputKind,
    hasSchema: Bool,
    schemaName: String?,
    schemaDescription: String?,
    enumValues: [String]?
) throws {
    switch output {
    case .noSchema:
        if hasSchema {
            throw InvalidArgumentError(
                parameter: "schema",
                message: "Schema is not supported for no-schema output."
            )
        }

        if let schemaDescription {
            throw InvalidArgumentError(
                parameter: "schemaDescription",
                value: .string(schemaDescription),
                message: "Schema description is not supported for no-schema output."
            )
        }

        if let schemaName {
            throw InvalidArgumentError(
                parameter: "schemaName",
                value: .string(schemaName),
                message: "Schema name is not supported for no-schema output."
            )
        }

        if let enumValues {
            let value = JSONValue.array(enumValues.map { JSONValue.string($0) })
            throw InvalidArgumentError(
                parameter: "enumValues",
                value: value,
                message: "Enum values are not supported for no-schema output."
            )
        }

    case .object:
        if !hasSchema {
            throw InvalidArgumentError(
                parameter: "schema",
                message: "Schema is required for object output."
            )
        }

        if let enumValues {
            let value = JSONValue.array(enumValues.map { JSONValue.string($0) })
            throw InvalidArgumentError(
                parameter: "enumValues",
                value: value,
                message: "Enum values are not supported for object output."
            )
        }

    case .array:
        if !hasSchema {
            throw InvalidArgumentError(
                parameter: "schema",
                message: "Element schema is required for array output."
            )
        }

        if let enumValues {
            let value = JSONValue.array(enumValues.map { JSONValue.string($0) })
            throw InvalidArgumentError(
                parameter: "enumValues",
                value: value,
                message: "Enum values are not supported for array output."
            )
        }

    case .enumeration:
        if hasSchema {
            throw InvalidArgumentError(
                parameter: "schema",
                message: "Schema is not supported for enum output."
            )
        }

        if let schemaDescription {
            throw InvalidArgumentError(
                parameter: "schemaDescription",
                value: .string(schemaDescription),
                message: "Schema description is not supported for enum output."
            )
        }

        if let schemaName {
            throw InvalidArgumentError(
                parameter: "schemaName",
                value: .string(schemaName),
                message: "Schema name is not supported for enum output."
            )
        }

        guard let enumValues, !enumValues.isEmpty else {
            throw InvalidArgumentError(
                parameter: "enumValues",
                message: "Enum values are required for enum output."
            )
        }
    }
}

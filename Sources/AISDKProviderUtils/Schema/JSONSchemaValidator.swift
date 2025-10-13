/**
 Lightweight JSON Schema validator for tool input schemas.

 Port of `@ai-sdk/provider-utils/src/schema.ts` (object/required validation paths).
 */
import AISDKProvider

/**
 Validates `JSONValue` instances against a subset of JSON Schema used by tool inputs.

 Port of `@ai-sdk/provider-utils/src/schema.ts` JSON schema validation behavior.
 Focused on the object/property/required semantics exercised by tool schemas.
 */
struct JSONSchemaValidator: Sendable {
    private let schema: JSONValue

    init(schema: JSONValue) {
        self.schema = schema
    }

    func validate(value: JSONValue) -> [JSONSchemaValidationIssue] {
        validate(value: value, schema: schema, path: [])
    }

    private func validate(
        value: JSONValue,
        schema: JSONValue,
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        guard case .object(let schemaObject) = schema else {
            // Non-object schemas are treated as permissive for now.
            return []
        }

        var issues: [JSONSchemaValidationIssue] = []

        if let type = schemaObject["type"], case .string(let typeString) = type {
            issues += validate(type: typeString, value: value, schema: schemaObject, path: path)
        }

        return issues
    }

    private func validate(
        type: String,
        value: JSONValue,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        switch type {
        case "object":
            return validateObject(value: value, schema: schema, path: path)
        case "string":
            if case .string = value {
                return []
            }
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected string, received \(value.typeDescription)"
            )]
        case "number":
            if case .number = value {
                return []
            }
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected number, received \(value.typeDescription)"
            )]
        case "boolean":
            if case .bool = value {
                return []
            }
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected boolean, received \(value.typeDescription)"
            )]
        case "array":
            guard case .array(let array) = value else {
                return [JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected array, received \(value.typeDescription)"
                )]
            }

            var issues: [JSONSchemaValidationIssue] = []

            if let items = schema["items"] {
                for (index, element) in array.enumerated() {
                    issues += validate(
                        value: element,
                        schema: items,
                        path: path + ["\(index)"]
                    )
                }
            }

            return issues

        default:
            return []
        }
    }

    private func validateObject(
        value: JSONValue,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        guard case .object(let object) = value else {
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected object, received \(value.typeDescription)"
            )]
        }

        var issues: [JSONSchemaValidationIssue] = []

        let properties = (schema["properties"]?.objectValue) ?? [:]
        let required = schema["required"]?.stringArrayValue ?? []

        for property in required where object[property] == nil {
            issues.append(
                JSONSchemaValidationIssue(
                    path: path + [property],
                    message: "Invalid input: missing required property '\(property)'."
                )
            )
        }

        for (name, propertySchema) in properties {
            if let value = object[name] {
                issues += validate(
                    value: value,
                    schema: propertySchema,
                    path: path + [name]
                )
            }
        }

        if let additionalProperties = schema["additionalProperties"] {
            switch additionalProperties {
            case .bool(let allowed) where !allowed:
                let allowedKeys = Set(properties.keys)
                for key in object.keys where !allowedKeys.contains(key) {
                    issues.append(
                        JSONSchemaValidationIssue(
                            path: path + [key],
                            message: "Invalid input: unexpected property '\(key)'."
                        )
                    )
                }
            case .object:
                let allowedKeys = Set(properties.keys)
                for (key, value) in object where !allowedKeys.contains(key) {
                    issues += validate(
                        value: value,
                        schema: additionalProperties,
                        path: path + [key]
                    )
                }
            default:
                break
            }
        }

        return issues
    }
}

struct JSONSchemaValidationIssue: Sendable, CustomStringConvertible {
    let path: [String]
    let message: String

    var description: String {
        if path.isEmpty {
            return message
        } else {
            return "\(path.joined(separator: ".")): \(message)"
        }
    }
}

struct JSONSchemaValidationIssuesError: Error, CustomStringConvertible, Sendable {
    let issues: [JSONSchemaValidationIssue]

    var description: String {
        issues.map(\.description).joined(separator: "; ")
    }
}

extension JSONValue {
    fileprivate var objectValue: [String: JSONValue]? {
        if case .object(let object) = self {
            return object
        }
        return nil
    }

    fileprivate var stringArrayValue: [String]? {
        guard case .array(let values) = self else {
            return nil
        }
        var result: [String] = []
        result.reserveCapacity(values.count)
        for entry in values {
            if case .string(let string) = entry {
                result.append(string)
            }
        }
        return result
    }

    fileprivate var typeDescription: String {
        switch self {
        case .string:
            return "string"
        case .number:
            return "number"
        case .bool:
            return "boolean"
        case .array:
            return "array"
        case .object:
            return "object"
        case .null:
            return "null"
        }
    }
}

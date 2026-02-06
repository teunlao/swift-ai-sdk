/**
 Lightweight JSON Schema validator for tool input schemas.

 Port of `@ai-sdk/provider-utils/src/schema.ts` (object/required validation paths).
 */
import Foundation
import AISDKProvider

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

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

        if let constValue = schemaObject["const"], value != constValue {
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected constant value."
            )]
        }

        if let type = schemaObject["type"] {
            let typeIssues = validate(type: type, value: value, schema: schemaObject, path: path)
            if !typeIssues.isEmpty {
                return typeIssues
            }
        }

        if let allowed = schemaObject["enum"]?.arrayValue, !allowed.isEmpty, !allowed.contains(value) {
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected one of the allowed values."
            )]
        }

        let stringIssues = validateStringKeywordsIfApplicable(value: value, schema: schemaObject, path: path)
        if !stringIssues.isEmpty {
            return stringIssues
        }

        if let allOf = schemaObject["allOf"]?.arrayValue, !allOf.isEmpty {
            let issues = allOf.flatMap { validate(value: value, schema: $0, path: path) }
            if !issues.isEmpty {
                return issues
            }
        }

        if let anyOf = schemaObject["anyOf"]?.arrayValue, !anyOf.isEmpty {
            let issues = validateAnyOf(value: value, schemas: anyOf, path: path)
            if !issues.isEmpty {
                return issues
            }
        }

        if let oneOf = schemaObject["oneOf"]?.arrayValue, !oneOf.isEmpty {
            let issues = validateOneOf(value: value, schemas: oneOf, path: path)
            if !issues.isEmpty {
                return issues
            }
        }

        return []
    }

    private func validate(
        type typeValue: JSONValue,
        value: JSONValue,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        switch typeValue {
        case .string(let typeString):
            return validate(type: typeString, value: value, schema: schema, path: path)
        case .array(let values):
            let types = values.compactMap { entry -> String? in
                if case .string(let string) = entry { return string }
                return nil
            }
            return validate(types: types, value: value, schema: schema, path: path)
        default:
            return []
        }
    }

    private func validate(
        types: [String],
        value: JSONValue,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        guard !types.isEmpty else {
            return []
        }

        if value == .null {
            return types.contains("null") ? [] : [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected \(types.joined(separator: " or ")), received null"
            )]
        }

        let nonNullTypes = types.filter { $0 != "null" }
        if nonNullTypes.count == 1, let onlyType = nonNullTypes.first {
            return validate(type: onlyType, value: value, schema: schema, path: path)
        }

        var bestIssues: [JSONSchemaValidationIssue]? = nil
        for type in nonNullTypes.isEmpty ? types : nonNullTypes {
            let issues = validate(type: type, value: value, schema: schema, path: path)
            if issues.isEmpty {
                return []
            }
            if bestIssues == nil || issues.count < (bestIssues?.count ?? Int.max) {
                bestIssues = issues
            }
        }

        return bestIssues ?? []
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
            guard case .string(let string) = value else {
                return [JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected string, received \(value.typeDescription)"
                )]
            }

            return validateStringKeywords(string: string, schema: schema, path: path)
        case "number":
            guard case .number(let number) = value else {
                return [JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected number, received \(value.typeDescription)"
                )]
            }

            return validateNumericBounds(number: number, schema: schema, path: path)
        case "integer":
            guard case .number(let number) = value else {
                return [JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected integer, received \(value.typeDescription)"
                )]
            }

            guard number.isFinite, number.rounded() == number else {
                return [JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected integer, received number"
                )]
            }

            return validateNumericBounds(number: number, schema: schema, path: path)
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

            if let minItems = schema["minItems"]?.doubleValue, array.count < Int(minItems) {
                issues.append(JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected at least \(Int(minItems)) items."
                ))
            }

            if let maxItems = schema["maxItems"]?.doubleValue, array.count > Int(maxItems) {
                issues.append(JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected at most \(Int(maxItems)) items."
                ))
            }

            if schema["uniqueItems"]?.boolValue == true {
                for i in 0..<array.count {
                    for j in (i + 1)..<array.count where array[i] == array[j] {
                        issues.append(JSONSchemaValidationIssue(
                            path: path,
                            message: "Invalid input: expected all items to be unique."
                        ))
                        break
                    }
                    if !issues.isEmpty {
                        break
                    }
                }
            }

            if let items = schema["items"] {
                switch items {
                case .array(let tupleSchemas):
                    for (index, element) in array.enumerated() {
                        if index < tupleSchemas.count {
                            issues += validate(
                                value: element,
                                schema: tupleSchemas[index],
                                path: path + ["\(index)"]
                            )
                            continue
                        }

                        if let additionalItems = schema["additionalItems"] {
                            switch additionalItems {
                            case .bool(let allowed) where !allowed:
                                issues.append(JSONSchemaValidationIssue(
                                    path: path + ["\(index)"],
                                    message: "Invalid input: unexpected array item."
                                ))
                            case .object:
                                issues += validate(
                                    value: element,
                                    schema: additionalItems,
                                    path: path + ["\(index)"]
                                )
                            default:
                                break
                            }
                        }
                    }

                default:
                    for (index, element) in array.enumerated() {
                        issues += validate(
                            value: element,
                            schema: items,
                            path: path + ["\(index)"]
                        )
                    }
                }
            }

            return issues
        case "null":
            if case .null = value {
                return []
            }
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected null, received \(value.typeDescription)"
            )]

        default:
            return []
        }
    }

    private func validateStringKeywordsIfApplicable(
        value: JSONValue,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        guard case .string(let string) = value else {
            return []
        }

        return validateStringKeywords(string: string, schema: schema, path: path)
    }

    private func validateStringKeywords(
        string: String,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        var issues: [JSONSchemaValidationIssue] = []
        let length = string.utf16.count

        if let minLength = schema["minLength"]?.doubleValue, length < Int(minLength) {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected string length >= \(Int(minLength))."
            ))
        }

        if let maxLength = schema["maxLength"]?.doubleValue, length > Int(maxLength) {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected string length <= \(Int(maxLength))."
            ))
        }

        if let pattern = schema["pattern"]?.stringValue,
           let regex = try? NSRegularExpression(pattern: pattern),
           regex.firstMatch(in: string, range: NSRange(location: 0, length: length)) == nil {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: string does not match required pattern."
            ))
        }

        if let format = schema["format"]?.stringValue,
           !isValidStringFormat(string, format: format) {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: string does not match required format."
            ))
        }

        if let contentEncoding = schema["contentEncoding"]?.stringValue,
           contentEncoding == "base64",
           Data(base64Encoded: string) == nil {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected base64-encoded string."
            ))
        }

        return issues
    }

    private func isValidStringFormat(_ string: String, format: String) -> Bool {
        switch format {
        case "email", "idn-email":
            return Self.emailRegex.firstMatch(
                in: string,
                range: NSRange(location: 0, length: string.utf16.count)
            ) != nil

        case "uri":
            return isValidURI(string)

        case "uuid":
            return UUID(uuidString: string) != nil

        case "ipv4":
            return isValidIPv4(string)

        case "ipv6":
            return isValidIPv6(string)

        case "date-time":
            return isValidDateTime(string)

        case "date":
            return isValidDate(string)

        case "time":
            return Self.timeRegex.firstMatch(
                in: string,
                range: NSRange(location: 0, length: string.utf16.count)
            ) != nil

        case "duration":
            return Self.durationRegex.firstMatch(
                in: string,
                range: NSRange(location: 0, length: string.utf16.count)
            ) != nil

        case "binary":
            return Data(base64Encoded: string) != nil

        default:
            return true
        }
    }

    private func isValidURI(_ string: String) -> Bool {
        guard let components = URLComponents(string: string),
              let scheme = components.scheme,
              !scheme.isEmpty
        else {
            return false
        }

        if let host = components.host {
            return !host.isEmpty
        }

        return !components.path.isEmpty
    }

    private func isValidIPv4(_ string: String) -> Bool {
        var address = in_addr()
        return string.withCString { inet_pton(AF_INET, $0, &address) } == 1
    }

    private func isValidIPv6(_ string: String) -> Bool {
        var address = in6_addr()
        return string.withCString { inet_pton(AF_INET6, $0, &address) } == 1
    }

    private func isValidDateTime(_ string: String) -> Bool {
        let formatter = ISO8601DateFormatter()
        if formatter.date(from: string) != nil {
            return true
        }

        let formatterWithFractional = ISO8601DateFormatter()
        formatterWithFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatterWithFractional.date(from: string) != nil
    }

    private func isValidDate(_ string: String) -> Bool {
        let parts = string.split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              (1...12).contains(month)
        else {
            return false
        }

        let daysInMonth: Int = {
            switch month {
            case 1, 3, 5, 7, 8, 10, 12:
                return 31
            case 4, 6, 9, 11:
                return 30
            case 2:
                let isLeapYear = (year % 4 == 0 && year % 100 != 0) || (year % 400 == 0)
                return isLeapYear ? 29 : 28
            default:
                return 0
            }
        }()

        return (1...daysInMonth).contains(day)
    }

    private static let emailRegex: NSRegularExpression = {
        // Port of zod3-to-json-schema's email regex.
        let pattern =
            "^(?!\\.)(?!.*\\.\\.)([a-zA-Z0-9_'+\\-\\.]*?)[a-zA-Z0-9_+-]@([a-zA-Z0-9][a-zA-Z0-9\\-]*\\.)+[a-zA-Z]{2,}$"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let timeRegex: NSRegularExpression = {
        // Rough approximation of Zod `.time()` validation.
        let pattern = "^([01]\\d|2[0-3]):[0-5]\\d:[0-5]\\d(\\.\\d+)?$"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private static let durationRegex: NSRegularExpression = {
        // Rough ISO-8601 duration validation, e.g. "P3DT4H", "PT0.5S".
        let pattern = "^P(?!$)(\\d+Y)?(\\d+M)?(\\d+D)?(T(\\d+H)?(\\d+M)?(\\d+(\\.\\d+)?S)?)?$"
        return try! NSRegularExpression(pattern: pattern)
    }()

    private func validateNumericBounds(
        number: Double,
        schema: [String: JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        var issues: [JSONSchemaValidationIssue] = []

        if let minimum = schema["minimum"]?.doubleValue, number < minimum {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected number >= \(minimum)."
            ))
        }

        if let maximum = schema["maximum"]?.doubleValue, number > maximum {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected number <= \(maximum)."
            ))
        }

        if let exclusiveMinimum = schema["exclusiveMinimum"]?.doubleValue, number <= exclusiveMinimum {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected number > \(exclusiveMinimum)."
            ))
        }

        if let exclusiveMaximum = schema["exclusiveMaximum"]?.doubleValue, number >= exclusiveMaximum {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected number < \(exclusiveMaximum)."
            ))
        }

        if let multipleOf = schema["multipleOf"]?.doubleValue, multipleOf != 0 {
            let remainder = number.truncatingRemainder(dividingBy: multipleOf)
            if abs(remainder) > 1e-9 && abs(remainder - multipleOf) > 1e-9 {
                issues.append(JSONSchemaValidationIssue(
                    path: path,
                    message: "Invalid input: expected number to be a multiple of \(multipleOf)."
                ))
            }
        }

        return issues
    }

    private func validateAnyOf(
        value: JSONValue,
        schemas: [JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        var bestIssues: [JSONSchemaValidationIssue]? = nil

        for schema in schemas {
            let issues = validate(value: value, schema: schema, path: path)
            if issues.isEmpty {
                return []
            }

            if bestIssues == nil || issues.count < (bestIssues?.count ?? Int.max) {
                bestIssues = issues
            }
        }

        return bestIssues ?? []
    }

    private func validateOneOf(
        value: JSONValue,
        schemas: [JSONValue],
        path: [String]
    ) -> [JSONSchemaValidationIssue] {
        var matching = 0
        var bestIssues: [JSONSchemaValidationIssue]? = nil

        for schema in schemas {
            let issues = validate(value: value, schema: schema, path: path)
            if issues.isEmpty {
                matching += 1
            } else if bestIssues == nil || issues.count < (bestIssues?.count ?? Int.max) {
                bestIssues = issues
            }
        }

        if matching == 1 {
            return []
        }

        if matching > 1 {
            return [JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected value to match exactly one schema."
            )]
        }

        return bestIssues ?? []
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

        if let minProperties = schema["minProperties"]?.doubleValue,
           object.count < Int(minProperties) {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected at least \(Int(minProperties)) properties."
            ))
        }

        if let maxProperties = schema["maxProperties"]?.doubleValue,
           object.count > Int(maxProperties) {
            issues.append(JSONSchemaValidationIssue(
                path: path,
                message: "Invalid input: expected at most \(Int(maxProperties)) properties."
            ))
        }

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

    fileprivate var arrayValue: [JSONValue]? {
        if case .array(let array) = self {
            return array
        }
        return nil
    }

    fileprivate var stringValue: String? {
        if case .string(let string) = self {
            return string
        }
        return nil
    }

    fileprivate var doubleValue: Double? {
        if case .number(let number) = self {
            return number
        }
        return nil
    }

    fileprivate var boolValue: Bool? {
        if case .bool(let bool) = self {
            return bool
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

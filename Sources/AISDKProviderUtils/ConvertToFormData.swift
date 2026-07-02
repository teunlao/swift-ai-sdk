import Foundation

/**
 A value that can be appended to multipart form data.

 Swift adaptation of the browser `FormData` value surface used by
 `@ai-sdk/provider-utils/src/convert-to-form-data.ts`.
 */
public enum FormDataValue: Sendable, Equatable {
    case string(String)
    case data(Data, filename: String = "blob", contentType: String? = nil)
}

extension FormDataValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .string(value)
    }
}

extension FormDataValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .string(String(value))
    }
}

extension FormDataValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .string(String(value))
    }
}

extension FormDataValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .string(String(value))
    }
}

/**
 A form-data field value. Arrays follow upstream `convertToFormData` key rules.
 */
public enum FormDataInputValue: Sendable, Equatable {
    case value(FormDataValue)
    case array([FormDataValue])
}

extension FormDataInputValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self = .value(.string(value))
    }
}

extension FormDataInputValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) {
        self = .value(.string(String(value)))
    }
}

extension FormDataInputValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) {
        self = .value(.string(String(value)))
    }
}

extension FormDataInputValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) {
        self = .value(.string(String(value)))
    }
}

/**
 Converts a Swift dictionary to multipart/form-data.

 Nullish values are represented as `nil` and skipped. Single-element arrays use
 the base key. Multi-element arrays use a `[]` suffix unless
 `useArrayBrackets` is false.
 */
public func convertToFormData(
    _ input: [String: FormDataInputValue?],
    useArrayBrackets: Bool = true,
    boundary: String = MultipartFormDataBuilder.makeBoundary()
) -> MultipartFormDataBuilder {
    var builder = MultipartFormDataBuilder(boundary: boundary)

    for (key, value) in input {
        guard let value else {
            continue
        }

        switch value {
        case .value(let value):
            builder.appendFormDataValue(value, name: key)

        case .array(let values):
            if values.count == 1, let value = values.first {
                builder.appendFormDataValue(value, name: key)
                continue
            }

            let arrayKey = useArrayBrackets ? "\(key)[]" : key
            for value in values {
                builder.appendFormDataValue(value, name: arrayKey)
            }
        }
    }

    return builder
}

/**
 Convenience overload for string-only form data.
 */
public func convertToFormData(
    _ input: [String: String?],
    useArrayBrackets: Bool = true,
    boundary: String = MultipartFormDataBuilder.makeBoundary()
) -> MultipartFormDataBuilder {
    var converted: [String: FormDataInputValue?] = [:]
    converted.reserveCapacity(input.count)

    for (key, value) in input {
        converted[key] = value.map { .value(.string($0)) }
    }

    return convertToFormData(
        converted,
        useArrayBrackets: useArrayBrackets,
        boundary: boundary
    )
}

private extension MultipartFormDataBuilder {
    mutating func appendFormDataValue(_ value: FormDataValue, name: String) {
        switch value {
        case .string(let string):
            appendField(name: name, value: string)
        case let .data(data, filename, contentType):
            appendFile(name: name, filename: filename, contentType: contentType, data: data)
        }
    }
}

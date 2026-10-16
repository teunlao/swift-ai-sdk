import Foundation

/// `JSON.stringify` for values embedded in error messages.
func stringifyErrorValue(_ value: Any?) -> String {
    guard let value else {
        return "null"
    }

    if let json = value as? JSONValue {
        return encodeJSON(json) ?? String(describing: json)
    }

    if JSONSerialization.isValidJSONObject(value),
       let data = try? JSONSerialization.data(withJSONObject: value, options: [.withoutEscapingSlashes]),
       let string = String(data: data, encoding: .utf8) {
        return string
    }

    if let string = value as? String {
        return encodeJSON(.string(string)) ?? string
    }

    if let bool = value as? Bool {
        return bool ? "true" : "false"
    }

    if let encodable = value as? any Encodable,
       let data = try? JSONEncoder().encode(encodable),
       let string = String(data: data, encoding: .utf8) {
        return string
    }

    return String(describing: value)
}

private func encodeJSON(_ value: JSONValue) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.withoutEscapingSlashes]
    guard let data = try? encoder.encode(value) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

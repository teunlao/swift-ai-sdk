import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Injects schema information into the prompt for JSON responses.

 Port of `@ai-sdk/ai/src/generate-object/inject-json-instruction.ts`.
 */
func injectJSONInstruction(
    prompt: String?,
    schema: JSONValue?,
    schemaPrefix: String? = nil,
    schemaSuffix: String? = nil
) -> String {
    let effectivePrefix: String?
    if let prefix = schemaPrefix {
        effectivePrefix = prefix
    } else if schema != nil {
        effectivePrefix = "JSON schema:"
    } else {
        effectivePrefix = nil
    }

    let effectiveSuffix: String
    if let suffix = schemaSuffix {
        effectiveSuffix = suffix
    } else if schema != nil {
        effectiveSuffix = "You MUST answer with a JSON object that matches the JSON schema above."
    } else {
        effectiveSuffix = "You MUST answer with JSON."
    }

    var lines: [String] = []

    if let prompt, !prompt.isEmpty {
        lines.append(prompt)
        lines.append("")
    }

    if let effectivePrefix {
        lines.append(effectivePrefix)
    }

    if let schema {
        if let schemaString = jsonString(from: schema) {
            lines.append(schemaString)
        }
    }

    lines.append(effectiveSuffix)

    return lines.joined(separator: "\n")
}

private func jsonString(from value: JSONValue) -> String? {
    let anyValue = jsonValueToAny(value)
    guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: [.sortedKeys]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func jsonValueToAny(_ value: JSONValue) -> Any {
    switch value {
    case .null: return NSNull()
    case .bool(let bool): return bool
    case .number(let number): return number
    case .string(let string): return string
    case .array(let array): return array.map { jsonValueToAny($0) }
    case .object(let object): return object.mapValues { jsonValueToAny($0) }
    }
}

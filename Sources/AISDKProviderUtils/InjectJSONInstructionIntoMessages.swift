import Foundation
import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/provider-utils/src/inject-json-instruction.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public func injectJSONInstructionIntoMessages(
    messages: LanguageModelV3Prompt,
    schema: JSONValue?,
    schemaPrefix: String? = nil,
    schemaSuffix: String? = nil
) -> LanguageModelV3Prompt {
    var remainingMessages = messages

    let systemMessage: LanguageModelV3Message
    if let first = messages.first, case let .system(content, providerOptions) = first {
        remainingMessages = Array(messages.dropFirst())
        let updatedContent = injectJSONInstruction(
            prompt: content,
            schema: schema,
            schemaPrefix: schemaPrefix,
            schemaSuffix: schemaSuffix
        )
        systemMessage = .system(content: updatedContent, providerOptions: providerOptions)
    } else {
        let updatedContent = injectJSONInstruction(
            prompt: nil,
            schema: schema,
            schemaPrefix: schemaPrefix,
            schemaSuffix: schemaSuffix
        )
        systemMessage = .system(content: updatedContent, providerOptions: nil)
    }

    return [systemMessage] + remainingMessages
}

private func injectJSONInstruction(
    prompt: String?,
    schema: JSONValue?,
    schemaPrefix: String?,
    schemaSuffix: String?
) -> String {
    let effectivePrefix: String?
    if let schemaPrefix {
        effectivePrefix = schemaPrefix
    } else if schema != nil {
        effectivePrefix = "JSON schema:"
    } else {
        effectivePrefix = nil
    }

    let effectiveSuffix: String
    if let schemaSuffix {
        effectiveSuffix = schemaSuffix
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

    if let schema,
       let schemaString = encodeJSONValue(schema) {
        lines.append(schemaString)
    }

    lines.append(effectiveSuffix)

    return lines.joined(separator: "\n")
}

private func encodeJSONValue(_ value: JSONValue) -> String? {
    let anyValue = jsonValueToJSONObject(value)
    guard JSONSerialization.isValidJSONObject(anyValue) else {
        return nil
    }
    guard let data = try? JSONSerialization.data(withJSONObject: anyValue, options: [.sortedKeys]) else {
        return nil
    }
    return String(data: data, encoding: .utf8)
}

private func jsonValueToJSONObject(_ value: JSONValue) -> Any {
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
        return array.map { jsonValueToJSONObject($0) }
    case .object(let object):
        return object.mapValues { jsonValueToJSONObject($0) }
    }
}

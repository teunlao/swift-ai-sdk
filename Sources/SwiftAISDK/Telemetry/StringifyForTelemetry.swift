import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Serializes a prompt for telemetry attributes.

 Port of `@ai-sdk/otel/src/stringify-for-telemetry.ts`: the data of a file part is
 written as its plain value (base64 bytes or URL string) instead of the tagged
 file-data object the prompt's own JSON coding uses.
 */
public func stringifyForTelemetry(_ prompt: LanguageModelV4Prompt) throws -> String {
    let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(prompt))
    guard case .array(let messages) = encoded else { return try telemetryJSONString(encoded) }
    return try telemetryJSONString(.array(messages.map(projectFileData)))
}

private func projectFileData(_ message: JSONValue) -> JSONValue {
    guard case .object(var object) = message, case .array(let content)? = object["content"] else {
        return message
    }
    object["content"] = .array(content.map { part in
        guard case .object(var filePart) = part, filePart["type"] == .string("file"),
              case .object(let data)? = filePart["data"] else { return part }
        switch data["type"] {
        case .string("data"): filePart["data"] = data["data"]
        case .string("url"): filePart["data"] = data["url"]
        default: break
        }
        return .object(filePart)
    })
    return .object(object)
}

private func telemetryJSONString(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

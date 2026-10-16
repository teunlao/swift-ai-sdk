import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Creates the tool result output sent to the model.

 Port of `@ai-sdk/ai/src/prompt/create-tool-model-output.ts`: `.text` and
 `.json` error modes produce error outputs; otherwise the tool's
 `toModelOutput` decides, and without it a string becomes text and any other
 value JSON.
 */
public func createToolModelOutput(
    toolCallId: String,
    input: JSONValue,
    output: Any?,
    tool: Tool?,
    errorMode: ToolOutputErrorMode
) async throws -> ToolResultOutput {
    switch errorMode {
    case .text:
        return .errorText(value: AISDKProvider.getErrorMessage(output))
    case .json:
        return .errorJson(value: toJSONValue(output))
    case .none:
        break
    }

    if let toModelOutput = tool?.toModelOutput {
        return try await toModelOutput(
            ToolModelOutputOptions(toolCallId: toolCallId, input: input, output: toJSONValue(output))
        )
    }

    // Swift tool outputs are JSON, so a JSON string is the upstream `typeof output === 'string'` case.
    if let stringOutput = output as? String {
        return .text(value: stringOutput)
    }
    if case .string(let stringOutput)? = output as? JSONValue {
        return .text(value: stringOutput)
    }

    return .json(value: toJSONValue(output))
}

/**
 Mode for handling tool output errors.

 - `none`: Normal output handling (not an error)
 - `text`: Convert output to error-text format
 - `json`: Convert output to error-json format
 */
public enum ToolOutputErrorMode: String, Sendable {
    case none
    case text
    case json
}

// MARK: - Helper Functions

/**
 Converts any value to JSONValue.

 Upstream behavior: `undefined` → `null`, all other values cast to JSONValue.
 Swift adaptation: `nil` → `.null`, others converted to JSONValue.

 - Parameter value: The value to convert
 - Returns: A JSONValue representation
 */
private func toJSONValue(_ value: Any?) -> JSONValue {
    // Handle nil → .null
    guard let value = value else {
        return .null
    }

    // Try to convert to JSONValue
    if let jsonValue = value as? JSONValue {
        return jsonValue
    }

    if value is NSNull {
        return .null
    }

    // Handle basic types
    if let string = value as? String {
        return .string(string)
    }
    if let number = value as? Int {
        return .number(Double(number))
    }
    if let number = value as? Double {
        return .number(number)
    }
    if let bool = value as? Bool {
        return .bool(bool)
    }
    if let array = value as? [Any] {
        return .array(array.map { toJSONValue($0) })
    }
    if let dict = value as? [String: Any] {
        return .object(dict.mapValues { toJSONValue($0) })
    }

    // Guard JSONSerialization to avoid Objective-C exceptions on invalid top-level fragments.
    if JSONSerialization.isValidJSONObject(value) {
        do {
            let data = try JSONSerialization.data(withJSONObject: value, options: [])
            let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
            return decoded
        } catch {
            // Fall through to string conversion below.
        }
    }

    return .string(String(describing: value))
}

import Foundation

/**
 Creates a tool result output in the LanguageModel V3 format.

 Port of `@ai-sdk/ai/src/prompt/create-tool-model-output.ts`.

 Handles different output modes:
 - `errorMode: .text` → converts output to error-text with string message
 - `errorMode: .json` → converts output to error-json with JSON value
 - `errorMode: .none` → normal result handling:
   - Uses tool.toModelOutput() if available
   - String output → text result
   - Other types → json result

 - Parameters:
   - output: The tool execution output (can be any type)
   - tool: Optional Tool instance with custom toModelOutput transformer
   - errorMode: How to handle the output (`.none`, `.text`, `.json`)
 - Returns: A LanguageModelV3ToolResultOutput ready for the model

 ## Example
 ```swift
 // Error text mode
 createToolModelOutput(
     output: "Connection failed",
     tool: nil,
     errorMode: .text
 )
 // → .errorText(value: "Connection failed")

 // Normal string output
 createToolModelOutput(
     output: "Success",
     tool: nil,
     errorMode: .none
 )
 // → .text(value: "Success")

 // Normal JSON output
 createToolModelOutput(
     output: ["result": "success", "code": 200],
     tool: nil,
     errorMode: .none
 )
 // → .json(value: JSONValue object)
 ```
 */
public func createToolModelOutput(
    output: Any?,
    tool: Tool?,
    errorMode: ToolOutputErrorMode
) -> LanguageModelV3ToolResultOutput {
    // Handle error modes first (priority over tool.toModelOutput)
    switch errorMode {
    case .text:
        return .errorText(value: getErrorMessage(output))
    case .json:
        return .errorJson(value: toJSONValue(output))
    case .none:
        break
    }

    // If tool has custom toModelOutput, use it
    // Swift adaptation: convert Any? → JSONValue before calling toModelOutput
    // TypeScript: tool.toModelOutput(output: unknown)
    // Swift: tool.toModelOutput(JSONValue) due to type safety
    if let tool = tool, let toModelOutput = tool.toModelOutput {
        let jsonOutput = toJSONValue(output)
        return toModelOutput(jsonOutput)
    }

    // Default handling: string → text, other → json
    if let stringOutput = output as? String {
        return .text(value: stringOutput)
    } else {
        return .json(value: toJSONValue(output))
    }
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

    // Fallback: try JSON serialization
    do {
        let data = try JSONSerialization.data(withJSONObject: value, options: [])
        let decoded = try JSONDecoder().decode(JSONValue.self, from: data)
        return decoded
    } catch {
        // If all else fails, convert to string and wrap in JSONValue
        return .string(String(describing: value))
    }
}


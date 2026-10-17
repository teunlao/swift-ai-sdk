import Foundation
import AISDKProvider
import AISDKProviderUtils

func convertToPerplexityInput(_ prompt: LanguageModelV4Prompt) throws -> PerplexityInputConversion {
    var input: [JSONValue] = []
    var warnings: [SharedV4Warning] = []
    func appendResult(_ part: LanguageModelV4ToolResultPart) throws {
        var value: JSONObject = ["type": "function_call_output", "call_id": .string(part.toolCallId), "name": .string(part.toolName), "output": .string(try perplexityToolOutput(part.output))]
        if let signature = perplexityThoughtSignature(part.providerOptions) { value["thought_signature"] = .string(signature) }
        input.append(.object(value))
    }
    for message in prompt {
        switch message {
        case .system(let text, _): input.append(["type": "message", "role": "system", "content": .string(text)])
        case .user(let parts, _):
            var content: [JSONValue] = []
            var text = ""
            var hasImage = false
            for part in parts {
                switch part {
                case .text(let part):
                    text += part.text
                    content.append(["type": "input_text", "text": .string(part.text)])
                case .file(let part):
                    guard getTopLevelMediaType(part.mediaType) == "image" else {
                        throw UnsupportedFunctionalityError(functionality: "file part media type \(part.mediaType)")
                    }
                    let url: String
                    switch part.data {
                    case .url(let value, let original): url = original ?? value.absoluteString
                    case .data(let value): url = "data:\(try resolveFullMediaType(part: part));base64,\(value.base64EncodedString())"
                    case .base64(let value): url = "data:\(try resolveFullMediaType(part: part));base64,\(value)"
                    case .reference: throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
                    case .text: throw UnsupportedFunctionalityError(functionality: "text file parts")
                    }
                    hasImage = true
                    content.append(["type": "input_image", "image_url": .string(url)])
                }
            }
            input.append(["type": "message", "role": "user", "content": hasImage ? .array(content) : .string(text)])
        case .assistant(let parts, _):
            let text = parts.compactMap { part -> String? in if case .text(let value) = part { return value.text }; return nil }.joined()
            if !text.isEmpty { input.append(["type": "message", "role": "assistant", "content": .string(text)]) }
            for part in parts {
                switch part {
                case .text: break
                case .toolCall(let call):
                    var value: JSONObject = ["type": "function_call", "call_id": .string(call.toolCallId), "name": .string(call.toolName), "arguments": .string(try perplexityJSONString(call.input == .null ? .object([:]) : call.input))]
                    if let signature = perplexityThoughtSignature(call.providerOptions) { value["thought_signature"] = .string(signature) }
                    input.append(.object(value))
                case .toolResult(let result): try appendResult(result)
                case .reasoning: warnings.append(.unsupported(feature: "reasoning content in prompt", details: nil))
                case .file: throw UnsupportedFunctionalityError(functionality: "assistant file parts")
                case .reasoningFile: throw UnsupportedFunctionalityError(functionality: "assistant reasoning-file parts")
                case .custom: throw UnsupportedFunctionalityError(functionality: "assistant custom parts")
                }
            }
        case .tool(let parts, _):
            for part in parts {
                switch part {
                case .toolResult(let result): try appendResult(result)
                case .toolApprovalResponse: throw UnsupportedFunctionalityError(functionality: "tool approval responses")
                }
            }
        }
    }
    return .init(input: input, warnings: warnings)
}

private func perplexityThoughtSignature(_ options: SharedV4ProviderOptions?) -> String? {
    if case .string(let signature) = options?["perplexity"]?["thoughtSignature"] { return signature }
    return nil
}

private func perplexityToolOutput(_ output: LanguageModelV4ToolResultOutput) throws -> String {
    switch output {
    case .text(let value, _), .errorText(let value, _): return value
    case .json(let value, _), .errorJson(let value, _): return try perplexityJSONString(value)
    case .executionDenied(let reason, _): return reason ?? "Tool call execution denied."
    case .content(let parts):
        var text = ""
        for part in parts {
            guard case .text(let value, _) = part else {
                throw UnsupportedFunctionalityError(functionality: "file and custom tool result content")
            }
            text += value
        }
        return text
    }
}

func perplexityJSONString<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

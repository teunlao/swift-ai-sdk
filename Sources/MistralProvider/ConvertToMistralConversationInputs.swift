import AISDKProvider
import AISDKProviderUtils

struct MistralConversationInputs {
    let inputs: [JSONValue]
    let instructions: String?
}

func convertToMistralConversationInputs(
    prompt: LanguageModelV4Prompt,
    toolNameMapping: ToolNameMapping
) throws -> MistralConversationInputs {
    var inputs: [JSONValue] = []
    var instructions: [String] = []
    var executions: Set<String> = []

    func appendToolResult(_ part: LanguageModelV4ToolResultPart) throws {
        let result: String
        if executions.contains(part.toolCallId) {
            var value: JSONValue = .null
            if case .json(let output, _) = part.output,
               case .object(let object) = output,
               case .object(let info) = object["info"] {
                // JSONValue's nil literal is JSON null; Optional.none expresses absence.
                value = info["result"].flatMap { value -> JSONValue? in value == .null ? Optional<JSONValue>.none : value } ?? .object(info)
            }
            if case .string(let text) = value { result = text }
            else { result = try mistralJSONString(value) }
        } else {
            let messages = try convertToMistralChatMessages(prompt: [.tool(content: [.toolResult(part)], providerOptions: nil)])
            guard case .object(let message) = messages.first,
                  case .string(let content) = message["content"] else {
                throw InvalidResponseDataError(data: messages, message: "Missing converted tool result")
            }
            result = content
        }
        inputs.append(["type": "function.result", "tool_call_id": .string(part.toolCallId), "result": .string(result)])
    }

    for message in prompt {
        switch message {
        case .system(let text, _):
            instructions.append(text)
        case .user:
            let messages = try convertToMistralChatMessages(prompt: [message])
            if case .object(let converted) = messages.first, let content = converted["content"] {
                inputs.append(["type": "message.input", "role": "user", "content": content])
            }
        case .assistant(let parts, _):
            var content: [JSONValue] = []
            func flush() {
                if !content.isEmpty {
                    inputs.append(["type": "message.input", "role": "assistant", "content": .array(content)])
                    content = []
                }
            }
            for part in parts {
                switch part {
                case .text(let text): content.append(["type": "text", "text": .string(text.text)])
                case .reasoning(let reasoning):
                    content.append(["type": "thinking", "thinking": [["type": "text", "text": .string(reasoning.text)]], "closed": true])
                case .toolCall(let call):
                    flush()
                    var name = call.toolName
                    var arguments = try mistralJSONString(call.input)
                    if call.providerExecuted == true {
                        let metadata = call.providerOptions?["mistral"]
                        let declaredName = metadata?["function"].flatMap { value -> JSONValue? in value == .null ? Optional<JSONValue>.none : value } ?? metadata?["name"]
                        if case .string(let value) = declaredName { name = value }
                        else { name = toolNameMapping.toProviderToolName(call.toolName) }
                        if case .object(let input) = call.input, case .string(let value) = input["arguments"] { arguments = value }
                        executions.insert(call.toolCallId)
                    }
                    inputs.append(["type": "function.call", "tool_call_id": .string(call.toolCallId), "name": .string(name), "arguments": .string(arguments)])
                case .toolResult(let result):
                    flush()
                    try appendToolResult(result)
                case .file:
                    throw UnsupportedFunctionalityError(functionality: "assistant content type: file")
                case .reasoningFile:
                    throw UnsupportedFunctionalityError(functionality: "assistant content type: reasoning-file")
                case .custom:
                    throw UnsupportedFunctionalityError(functionality: "assistant content type: custom")
                }
            }
            flush()
        case .tool(let parts, _):
            for part in parts {
                if case .toolResult(let result) = part { try appendToolResult(result) }
            }
        }
    }
    return .init(inputs: inputs, instructions: instructions.isEmpty ? nil : instructions.joined(separator: "\n\n"))
}

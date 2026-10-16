import AISDKProvider

struct OpenAICompletionPromptBuilder {
    static func convert(
        prompt originalPrompt: LanguageModelV4Prompt,
        userLabel: String = "user",
        assistantLabel: String = "assistant"
    ) throws -> (prompt: String, stopSequences: [String]?) {
        var prompt = originalPrompt
        var text = ""
        if let first = prompt.first, case .system(let content, _) = first {
            text += content + "\n\n"
            prompt.removeFirst()
        }
        for message in prompt {
            switch message {
            case .system:
                throw InvalidPromptError(
                    prompt: String(describing: prompt),
                    message: "Unexpected system message in prompt: ${content}"
                )
            case .user(let parts, _):
                let content = parts.compactMap { part -> String? in
                    if case .text(let part) = part { return part.text }
                    return nil
                }.joined()
                text += "\(userLabel):\n\(content)\n\n"
            case .assistant(let parts, _):
                let content = try parts.compactMap { part -> String? in
                    switch part {
                    case .text(let part): return part.text
                    case .toolCall: throw UnsupportedFunctionalityError(functionality: "tool-call messages")
                    case .file, .custom, .reasoning, .reasoningFile, .toolResult: return nil
                    }
                }.joined()
                text += "\(assistantLabel):\n\(content)\n\n"
            case .tool:
                throw UnsupportedFunctionalityError(functionality: "tool messages")
            }
        }
        text += "\(assistantLabel):\n"
        return (text, ["\n\(userLabel):"])
    }
}

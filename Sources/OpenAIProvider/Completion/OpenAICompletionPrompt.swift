import Foundation
import AISDKProvider

struct OpenAICompletionPromptBuilder {
    static func convert(
        prompt originalPrompt: LanguageModelV3Prompt,
        userLabel: String = "user",
        assistantLabel: String = "assistant"
    ) throws -> (prompt: String, stopSequences: [String]?) {
        guard !originalPrompt.isEmpty else {
            let stop = "\n\(userLabel):"
            return ("\(assistantLabel):\n", [stop])
        }

        var prompt = originalPrompt
        var text = ""
        let promptDescription = String(describing: originalPrompt)

        if case .system(let content, _) = prompt[0] {
            text.append(content)
            text.append("\n\n")
            prompt = Array(prompt.dropFirst())
        }

        for message in prompt {
            switch message {
            case .system(let content, _):
                throw InvalidPromptError(prompt: promptDescription, message: "Unexpected system message in prompt: \(content)")
            case .user(let parts, _):
                let messageText = try parts.map { part -> String in
                    switch part {
                    case .text(let textPart):
                        return textPart.text
                    case .file:
                        throw UnsupportedFunctionalityError(functionality: "file message parts")
                    }
                }.joined()
                text.append("\(userLabel):\n")
                text.append(messageText)
                text.append("\n\n")
            case .assistant(let parts, _):
                let messageText = try parts.map { part -> String in
                    switch part {
                    case .text(let textPart):
                        return textPart.text
                    case .toolCall:
                        throw UnsupportedFunctionalityError(functionality: "tool-call messages")
                    case .toolResult:
                        throw UnsupportedFunctionalityError(functionality: "tool-result messages")
                    case .reasoning:
                        throw UnsupportedFunctionalityError(functionality: "reasoning messages")
                    case .file:
                        throw UnsupportedFunctionalityError(functionality: "file message parts")
                    }
                }.joined()
                text.append("\(assistantLabel):\n")
                text.append(messageText)
                text.append("\n\n")
            case .tool:
                throw UnsupportedFunctionalityError(functionality: "tool messages")
            }
        }

        text.append("\(assistantLabel):\n")
        let stop = "\n\(userLabel):"
        return (text, [stop])
    }
}

import Foundation
import AISDKProvider

public struct OpenAICompatibleCompletionPromptConversion {
    public let prompt: String
    public let stopSequences: [String]?
}

public enum OpenAICompatibleCompletionPromptConverter {
    public static func convert(
        prompt: LanguageModelV3Prompt,
        user: String = "user",
        assistant: String = "assistant"
    ) throws -> OpenAICompatibleCompletionPromptConversion {
        var prompt = prompt
        var text = ""

        if let first = prompt.first, case .system(let content, _) = first {
            text += "\(content)\n\n"
            prompt = Array(prompt.dropFirst())
        }

        for message in prompt {
            switch message {
            case .system:
                throw InvalidPromptError(prompt: String(describing: prompt), message: "Unexpected system message in completion prompt")
            case .user(let parts, _):
                let userMessage = try parts.map { part -> String in
                    switch part {
                    case .text(let textPart):
                        return textPart.text
                    case .file:
                        throw UnsupportedFunctionalityError(functionality: "file parts in completion prompts")
                    }
                }.joined()
                text += "\(user):\n\(userMessage)\n\n"
            case .assistant(let parts, _):
                let assistantMessage = try parts.map { part -> String in
                    switch part {
                    case .text(let textPart):
                        return textPart.text
                    case .toolCall:
                        throw UnsupportedFunctionalityError(functionality: "tool-call messages in completion prompts")
                    case .reasoning:
                        throw UnsupportedFunctionalityError(functionality: "reasoning content in completion prompts")
                    case .file:
                        throw UnsupportedFunctionalityError(functionality: "file content in completion prompts")
                    case .toolResult:
                        throw UnsupportedFunctionalityError(functionality: "tool results in completion prompts")
                    }
                }.joined()
                text += "\(assistant):\n\(assistantMessage)\n\n"
            case .tool:
                throw UnsupportedFunctionalityError(functionality: "tool messages in completion prompts")
            }
        }

        text += "\(assistant):\n"
        let stopSequences = ["\n\(user):"]

        return OpenAICompatibleCompletionPromptConversion(prompt: text, stopSequences: stopSequences)
    }
}

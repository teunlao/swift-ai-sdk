import SwiftAISDK

func getLastUserMessageText(prompt: LanguageModelV3Prompt) -> String? {
  guard let lastMessage = prompt.last else { return nil }
  guard case .user(let content, _) = lastMessage else { return nil }

  let text = content.compactMap { part -> String? in
    switch part {
    case .text(let textPart):
      return textPart.text
    case .file:
      return nil
    }
  }.joined(separator: "\n")

  return text.isEmpty ? nil : text
}


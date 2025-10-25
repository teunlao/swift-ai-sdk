import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/perplexity/src/convert-to-perplexity-messages.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

func convertToPerplexityMessages(_ prompt: LanguageModelV3Prompt) throws -> [PerplexityMessage] {
    var messages: [PerplexityMessage] = []

    for message in prompt {
        switch message {
        case .system(let content, _):
            messages.append(.init(role: .system, content: .text(content)))

        case .user(let parts, _):
            let hasImage = parts.contains { part in
                if case let .file(filePart) = part {
                    return filePart.mediaType.lowercased().hasPrefix("image/")
                }
                return false
            }

            let mapped = try parts.map { try convertUserPart($0) }
            let content: PerplexityMessage.Content
            if hasImage {
                content = .rich(mapped)
            } else {
                content = .text(joinText(mapped))
            }
            messages.append(.init(role: .user, content: content))

        case .assistant(let parts, _):
            let hasImage = parts.contains { part in
                if case let .file(filePart) = part {
                    return filePart.mediaType.lowercased().hasPrefix("image/")
                }
                return false
            }

            let mapped = parts.compactMap { convertAssistantPart($0) }
            let content: PerplexityMessage.Content
            if hasImage {
                content = .rich(mapped)
            } else {
                content = .text(joinText(mapped))
            }
            messages.append(.init(role: .assistant, content: content))

        case .tool:
            throw UnsupportedFunctionalityError(functionality: "Tool messages")
        }
    }

    return messages
}

// MARK: - Helpers

private func joinText(_ contents: [PerplexityMessageContent]) -> String {
    contents.compactMap { content in
        if case let .text(text) = content.kind {
            return text
        }
        return nil
    }.joined()
}

private func convertUserPart(_ part: LanguageModelV3UserMessagePart) throws -> PerplexityMessageContent {
    switch part {
    case .text(let textPart):
        return PerplexityMessageContent(kind: .text(textPart.text))
    case .file(let filePart):
        return try convertFilePart(filePart)
    }
}

private func convertAssistantPart(_ part: LanguageModelV3MessagePart) -> PerplexityMessageContent? {
    switch part {
    case .text(let textPart):
        return PerplexityMessageContent(kind: .text(textPart.text))
    case .file(let filePart):
        return try? convertFilePart(filePart)
    default:
        return nil
    }
}

private func convertFilePart(_ filePart: LanguageModelV3FilePart) throws -> PerplexityMessageContent {
    let mediaType = filePart.mediaType
    let imageURL: String

    switch filePart.data {
    case .url(let url):
        imageURL = url.absoluteString
    case .base64(let base64):
        imageURL = "data:\(mediaType);base64,\(base64)"
    case .data(let data):
        imageURL = "data:\(mediaType);base64,\(convertDataToBase64(data))"
    }

    return PerplexityMessageContent(kind: .imageURL(imageURL))
}

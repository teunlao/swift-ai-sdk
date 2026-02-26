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
            let hasMultipartContent = parts.contains { part in
                guard case let .file(filePart) = part else { return false }
                let mediaType = filePart.mediaType.lowercased()
                return mediaType.hasPrefix("image/") || mediaType == "application/pdf"
            }

            let mapped = try parts.enumerated().compactMap { index, part in
                try convertUserPart(part, index: index)
            }
            let content: PerplexityMessage.Content
            if hasMultipartContent {
                content = .rich(mapped)
            } else {
                content = .text(joinText(mapped))
            }
            messages.append(.init(role: .user, content: content))

        case .assistant(let parts, _):
            let hasMultipartContent = parts.contains { part in
                guard case let .file(filePart) = part else { return false }
                let mediaType = filePart.mediaType.lowercased()
                return mediaType.hasPrefix("image/") || mediaType == "application/pdf"
            }

            let mapped = parts.enumerated().compactMap { index, part in
                convertAssistantPart(part, index: index)
            }
            let content: PerplexityMessage.Content
            if hasMultipartContent {
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

private func convertUserPart(_ part: LanguageModelV3UserMessagePart, index: Int) throws -> PerplexityMessageContent? {
    switch part {
    case .text(let textPart):
        return PerplexityMessageContent(kind: .text(textPart.text))
    case .file(let filePart):
        return try convertFilePart(filePart, index: index)
    }
}

private func convertAssistantPart(_ part: LanguageModelV3MessagePart, index: Int) -> PerplexityMessageContent? {
    switch part {
    case .text(let textPart):
        return PerplexityMessageContent(kind: .text(textPart.text))
    case .file(let filePart):
        return try? convertFilePart(filePart, index: index)
    default:
        return nil
    }
}

private func convertFilePart(_ filePart: LanguageModelV3FilePart, index: Int) throws -> PerplexityMessageContent? {
    let mediaType = filePart.mediaType
    let lowercased = mediaType.lowercased()

    if lowercased == "application/pdf" {
        let fileName: String?
        let url: String

        switch filePart.data {
        case .url(let fileURL):
            url = fileURL.absoluteString
            fileName = filePart.filename
        case .base64(let base64):
            url = base64
            fileName = filePart.filename ?? "document-\(index).pdf"
        case .data(let data):
            url = convertDataToBase64(data)
            fileName = filePart.filename ?? "document-\(index).pdf"
        }

        return PerplexityMessageContent(kind: .fileURL(url: url, fileName: fileName))
    }

    guard lowercased.hasPrefix("image/") else {
        // Upstream silently ignores unsupported file types (filtered out).
        return nil
    }

    let imageURL: String

    switch filePart.data {
    case .url(let url):
        imageURL = url.absoluteString
    case .base64(let base64):
        let resolved = mediaType.isEmpty ? "image/jpeg" : mediaType
        imageURL = "data:\(resolved);base64,\(base64)"
    case .data(let data):
        let resolved = mediaType.isEmpty ? "image/jpeg" : mediaType
        imageURL = "data:\(resolved);base64,\(convertDataToBase64(data))"
    }

    return PerplexityMessageContent(kind: .imageURL(imageURL))
}

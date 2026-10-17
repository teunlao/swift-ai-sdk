import AISDKProvider

public func extractTextContent(content: [LanguageModelV4Content]) -> String? {
    let parts = content.compactMap { part -> String? in
        guard case .text(let text) = part else { return nil }
        return text.text
    }
    return parts.isEmpty ? nil : parts.joined()
}

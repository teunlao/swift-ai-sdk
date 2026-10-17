import AISDKProvider

public func extractReasoningContent(content: [LanguageModelV4Content]) -> String? {
    let parts = content.compactMap { part -> String? in
        guard case .reasoning(let reasoning) = part else { return nil }
        return reasoning.text
    }
    return parts.isEmpty ? nil : parts.joined(separator: "\n")
}

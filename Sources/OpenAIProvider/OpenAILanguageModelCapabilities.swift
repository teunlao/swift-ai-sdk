import Foundation

struct OpenAILanguageModelCapabilities: Sendable, Equatable {
    let isReasoningModel: Bool
    let systemMessageMode: OpenAIResponsesSystemMessageMode
    let supportsFlexProcessing: Bool
    let supportsPriorityProcessing: Bool
    let supportsConfigurationUpdate: Bool
    let supportsAsyncToolCalling: Bool
    let supportedReasoningEfforts: [String]?
    let supportsNonReasoningParameters: Bool
}

func getOpenAILanguageModelCapabilities(for modelId: String) -> OpenAILanguageModelCapabilities {
    func captures(_ pattern: String) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: modelId, range: NSRange(modelId.startIndex..., in: modelId)) else {
            return nil
        }
        return (1..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : (modelId as NSString).substring(with: range)
        }
    }
    // Match JavaScript's ASCII digits, strict end, and four dot-excluded line terminators.
    let oVersion = captures(#"^o([0-9]+)(?:-|\z)"#)?.first.flatMap { $0 }.flatMap(Double.init)
    let gpt = captures(#"^gpt-([0-9]+)(?:\.([0-9]+))?(?:-([^\n\r\u2028\u2029]+))?\z"#)
    let major = gpt?[0].flatMap(Double.init)
    let minor = gpt?[1].flatMap(Double.init)
    let variant = gpt?[2]
    let chat = minor == nil && (variant?.utf8.starts(with: "chat".utf8) ?? false)
    let nano = variant?.utf8.starts(with: "nano".utf8) ?? false
    let gpt6 = (major ?? 0) >= 6
    let solOrLuna = modelId == "gpt-6-sol" || modelId == "gpt-6-luna"
    let reasoning = oVersion != nil || ((major ?? 0) >= 5 && !chat)
    return OpenAILanguageModelCapabilities(
        isReasoningModel: reasoning,
        systemMessageMode: reasoning ? .developer : .system,
        supportsFlexProcessing: (oVersion ?? 0) >= 3 || ((major ?? 0) >= 5 && !chat),
        supportsPriorityProcessing: modelId.utf8.starts(with: "gpt-4".utf8) || ((major ?? 0) >= 5 && !nano && !chat) || (oVersion ?? 0) >= 3,
        supportsConfigurationUpdate: gpt6,
        supportsAsyncToolCalling: gpt6,
        supportedReasoningEfforts: solOrLuna ? ["none", "low", "medium", "high", "xhigh", "max"] : (gpt6 ? ["low", "medium", "high", "xhigh", "max"] : nil),
        supportsNonReasoningParameters: solOrLuna || (!gpt6 && ((major ?? 0) > 5 || (major == 5 && (minor ?? 0) >= 1)))
    )
}

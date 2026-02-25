import AISDKProvider

/// Converts MoonshotAI chat usage data to the shared V3 usage shape.
///
/// Mirrors `packages/moonshotai/src/convert-moonshotai-chat-usage.ts`.
public func convertMoonshotAIChatUsage(_ usage: JSONValue?) -> LanguageModelV3Usage {
    guard let usage, usage != .null else { return LanguageModelV3Usage() }
    guard case .object(let dict) = usage else {
        return LanguageModelV3Usage(raw: usage)
    }

    func intOrZero(_ value: JSONValue?) -> Int {
        guard let value, value != .null else { return 0 }
        switch value {
        case .number(let number):
            return Int(number)
        default:
            return 0
        }
    }

    let promptTokens = intOrZero(dict["prompt_tokens"])
    let completionTokens = intOrZero(dict["completion_tokens"])

    let cacheReadTokens: Int = {
        if let cached = dict["cached_tokens"] {
            let value = intOrZero(cached)
            if value != 0 { return value }
        }

        if case .object(let promptDetails)? = dict["prompt_tokens_details"] {
            return intOrZero(promptDetails["cached_tokens"])
        }

        return 0
    }()

    let reasoningTokens: Int = {
        if case .object(let completionDetails)? = dict["completion_tokens_details"] {
            return intOrZero(completionDetails["reasoning_tokens"])
        }
        return 0
    }()

    return LanguageModelV3Usage(
        inputTokens: .init(
            total: promptTokens,
            noCache: promptTokens - cacheReadTokens,
            cacheRead: cacheReadTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: completionTokens,
            text: completionTokens - reasoningTokens,
            reasoning: reasoningTokens
        ),
        raw: usage
    )
}


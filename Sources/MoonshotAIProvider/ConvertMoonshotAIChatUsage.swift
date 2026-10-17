import AISDKProvider

/// Converts MoonshotAI chat usage data to the shared V4 usage shape.
///
/// Mirrors `packages/moonshotai/src/convert-moonshotai-chat-usage.ts`.
public func convertMoonshotAIChatUsage(_ usage: JSONValue?) -> LanguageModelV4Usage {
    guard let usage, usage != .null else { return LanguageModelV4Usage() }
    guard case .object(let dict) = usage else {
        return LanguageModelV4Usage(raw: usage)
    }

    func intOrZero(_ value: JSONValue?) -> Int? {
        guard let value, value != .null else { return 0 }
        guard case .number(let number) = value else { return nil }
        return Int(exactly: number)
    }

    func subtract(_ total: Int?, _ part: Int?) -> Int? {
        guard let total, let part else { return nil }
        let difference = total.subtractingReportingOverflow(part)
        return difference.overflow ? nil : difference.partialValue
    }

    let promptTokens = intOrZero(dict["prompt_tokens"])
    let completionTokens = intOrZero(dict["completion_tokens"])

    let cacheReadTokens: Int? = {
        if let cached = dict["cached_tokens"], cached != .null { return intOrZero(cached) }

        if case .object(let promptDetails)? = dict["prompt_tokens_details"] {
            return intOrZero(promptDetails["cached_tokens"])
        }

        return 0
    }()

    let reasoningTokens: Int? = {
        if case .object(let completionDetails)? = dict["completion_tokens_details"] {
            return intOrZero(completionDetails["reasoning_tokens"])
        }
        return 0
    }()

    return LanguageModelV4Usage(
        inputTokens: .init(
            total: promptTokens,
            noCache: subtract(promptTokens, cacheReadTokens),
            cacheRead: cacheReadTokens,
            cacheWrite: nil
        ),
        outputTokens: .init(
            total: completionTokens,
            text: subtract(completionTokens, reasoningTokens).map { max(0, $0) },
            reasoning: reasoningTokens
        ),
        raw: usage
    )
}


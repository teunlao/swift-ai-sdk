import Foundation
import AISDKProvider
import OpenAICompatibleProvider

private struct DeepSeekUsage: Sendable, Equatable {
    let promptCacheHitTokens: Double?
    let promptCacheMissTokens: Double?
}

private final class DeepSeekUsageStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var usage: DeepSeekUsage?

    func store(_ value: DeepSeekUsage) {
        lock.lock()
        usage = value
        lock.unlock()
    }

    func current() -> DeepSeekUsage? {
        lock.lock()
        let value = usage
        lock.unlock()
        return value
    }
}

private func buildDeepSeekMetadata(from usage: DeepSeekUsage?) -> SharedV3ProviderMetadata? {
    guard let usage else { return nil }

    let metadata: [String: JSONValue] = [
        "promptCacheHitTokens": .number(usage.promptCacheHitTokens ?? .nan),
        "promptCacheMissTokens": .number(usage.promptCacheMissTokens ?? .nan)
    ]

    return ["deepseek": metadata]
}

private func parseUsage(from value: JSONValue?) -> DeepSeekUsage? {
    guard let value, case .object(let object) = value else { return nil }

    let hitTokens = parseOptionalNumber(object["prompt_cache_hit_tokens"])
    let missTokens = parseOptionalNumber(object["prompt_cache_miss_tokens"])

    return DeepSeekUsage(
        promptCacheHitTokens: hitTokens,
        promptCacheMissTokens: missTokens
    )
}

private func parseOptionalNumber(_ value: JSONValue?) -> Double? {
    guard let value else { return nil }
    switch value {
    case .number(let number):
        return number
    case .null:
        return nil
    default:
        return nil
    }
}

private func extractUsage(from root: JSONValue) -> DeepSeekUsage? {
    guard case .object(let object) = root else { return nil }
    return parseUsage(from: object["usage"])
}

private func finishReasonIsStop(_ root: JSONValue) -> Bool {
    guard case .object(let object) = root,
          let choicesValue = object["choices"],
          case .array(let choices) = choicesValue,
          let first = choices.first,
          case .object(let choice) = first,
          let finishValue = choice["finish_reason"] else {
        return false
    }

    if case .string(let reason) = finishValue {
        return reason == "stop"
    }

    return false
}

public let deepSeekMetadataExtractor = OpenAICompatibleMetadataExtractor(
    extractMetadata: { parsedBody in
        buildDeepSeekMetadata(from: extractUsage(from: parsedBody))
    },
    createStreamExtractor: {
        let storage = DeepSeekUsageStorage()

        return OpenAICompatibleStreamMetadataExtractor(
            processChunk: { chunk in
                guard finishReasonIsStop(chunk), let usage = extractUsage(from: chunk) else { return }
                storage.store(usage)
            },
            buildMetadata: {
                buildDeepSeekMetadata(from: storage.current())
            }
        )
    }
)

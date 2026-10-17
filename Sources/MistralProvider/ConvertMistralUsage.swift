import Foundation
import AISDKProvider

struct MistralUsage: Codable, Sendable {
    let raw: JSONValue
    let promptTokens: Int?
    let completionTokens: Int?
    let cacheReadTokens: Int?
    let noCacheTokens: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode(JSONValue.self)
        guard case .object(let value) = raw else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected Mistral usage object")
        }
        func number(_ key: String, in object: [String: JSONValue], required: Bool = false) throws -> Double? {
            guard let value = object[key], value != .null else {
                if required { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Missing \(key)") }
                return nil
            }
            guard case .number(let number) = value, number.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected finite number for \(key)")
            }
            return number
        }
        let prompt = try number("prompt_tokens", in: value, required: true)!
        let completion = try number("completion_tokens", in: value, required: true)!
        promptTokens = Int(exactly: prompt)
        completionTokens = Int(exactly: completion)
        _ = try number("total_tokens", in: value, required: true)
        for key in ["prompt_audio_seconds", "request_count"] { _ = try number(key, in: value) }
        if let tier = value["service_tier"], tier != .null, case .string = tier {} else if value["service_tier"] != nil && value["service_tier"] != .null {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected service_tier string")
        }
        var cached = try number("num_cached_tokens", in: value)
        for key in ["prompt_tokens_details", "prompt_token_details", "completion_tokens_details"] {
            guard let details = value[key], details != .null else { continue }
            guard case .object(let object) = details else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected \(key) object")
            }
            if key == "completion_tokens_details" { _ = try number("reasoning_tokens", in: object) }
            else {
                let detailCached = try number("cached_tokens", in: object)
                if cached == nil { cached = detailCached }
                _ = try number("audio_tokens", in: object)
                if let messages = object["messages"], messages != .null, case .array = messages {} else if object["messages"] != nil && object["messages"] != .null {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected messages array")
                }
            }
        }
        let read = cached ?? 0
        cacheReadTokens = Int(exactly: read)
        if let promptTokens, let cacheReadTokens {
            let difference = promptTokens.subtractingReportingOverflow(cacheReadTokens)
            noCacheTokens = difference.overflow ? nil : difference.partialValue
        } else { noCacheTokens = Int(exactly: prompt - read) }
    }

    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}

func convertMistralUsage(_ usage: MistralUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    return .init(
        inputTokens: .init(total: usage.promptTokens, noCache: usage.noCacheTokens,
                           cacheRead: usage.cacheReadTokens == 0 ? nil : usage.cacheReadTokens),
        outputTokens: .init(total: usage.completionTokens, text: usage.completionTokens),
        raw: usage.raw
    )
}

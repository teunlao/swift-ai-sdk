import Foundation
import AISDKProvider

public struct AlibabaUsage: Sendable, Equatable, Codable {
    public struct PromptTokensDetails: Sendable, Equatable, Codable {
        public let cachedTokens: Double?
        public let cacheCreationInputTokens: Double?
        public let cacheType: String?
        private let original: JSONObject?
        public init(cachedTokens: Double? = nil, cacheCreationInputTokens: Double? = nil, cacheType: String? = nil) {
            self.cachedTokens = cachedTokens; self.cacheCreationInputTokens = cacheCreationInputTokens; self.cacheType = cacheType
            original = nil
        }
        private enum Keys: String, CodingKey { case cachedTokens = "cached_tokens", cacheCreationInputTokens = "cache_creation_input_tokens", cacheType = "cache_type" }
        public init(from decoder: Decoder) throws {
            original = try decoder.singleValueContainer().decode(JSONObject.self)
            let values = try decoder.container(keyedBy: Keys.self)
            cachedTokens = try values.decodeIfPresent(Double.self, forKey: .cachedTokens)
            cacheCreationInputTokens = try values.decodeIfPresent(Double.self, forKey: .cacheCreationInputTokens)
            cacheType = try values.decodeIfPresent(String.self, forKey: .cacheType)
        }
        var fields: JSONObject {
            if let original { return original }
            var fields: JSONObject = [:]
            if let cachedTokens { fields["cached_tokens"] = .number(cachedTokens) }
            if let cacheCreationInputTokens { fields["cache_creation_input_tokens"] = .number(cacheCreationInputTokens) }
            if let cacheType { fields["cache_type"] = .string(cacheType) }
            return fields
        }
        public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    }
    public struct CompletionTokensDetails: Sendable, Equatable, Codable {
        public let reasoningTokens: Double?
        private let original: JSONObject?
        public init(reasoningTokens: Double? = nil) { self.reasoningTokens = reasoningTokens; original = nil }
        private enum Keys: String, CodingKey { case reasoningTokens = "reasoning_tokens" }
        public init(from decoder: Decoder) throws {
            original = try decoder.singleValueContainer().decode(JSONObject.self)
            reasoningTokens = try decoder.container(keyedBy: Keys.self).decodeIfPresent(Double.self, forKey: .reasoningTokens)
        }
        var fields: JSONObject { original ?? reasoningTokens.map { ["reasoning_tokens": .number($0)] } ?? [:] }
        public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
    }
    public let promptTokens: Double?
    public let completionTokens: Double?
    public let totalTokens: Double?
    public let promptTokensDetails: PromptTokensDetails?
    public let completionTokensDetails: CompletionTokensDetails?
    private let original: JSONObject?

    public init(promptTokens: Double? = nil, completionTokens: Double? = nil, totalTokens: Double? = nil,
                promptTokensDetails: PromptTokensDetails? = nil, completionTokensDetails: CompletionTokensDetails? = nil) {
        self.promptTokens = promptTokens; self.completionTokens = completionTokens; self.totalTokens = totalTokens
        self.promptTokensDetails = promptTokensDetails; self.completionTokensDetails = completionTokensDetails; original = nil
    }
    private enum Keys: String, CodingKey { case promptTokens = "prompt_tokens", completionTokens = "completion_tokens", totalTokens = "total_tokens", promptTokensDetails = "prompt_tokens_details", completionTokensDetails = "completion_tokens_details" }
    public init(from decoder: Decoder) throws {
        original = try decoder.singleValueContainer().decode(JSONObject.self)
        let values = try decoder.container(keyedBy: Keys.self)
        promptTokens = try values.decodeIfPresent(Double.self, forKey: .promptTokens)
        completionTokens = try values.decodeIfPresent(Double.self, forKey: .completionTokens)
        totalTokens = try values.decodeIfPresent(Double.self, forKey: .totalTokens)
        promptTokensDetails = try values.decodeIfPresent(PromptTokensDetails.self, forKey: .promptTokensDetails)
        completionTokensDetails = try values.decodeIfPresent(CompletionTokensDetails.self, forKey: .completionTokensDetails)
    }
    var fields: JSONObject {
        if let original { return original }
        var fields: JSONObject = [:]
        if let promptTokens { fields["prompt_tokens"] = .number(promptTokens) }
        if let completionTokens { fields["completion_tokens"] = .number(completionTokens) }
        if let totalTokens { fields["total_tokens"] = .number(totalTokens) }
        if let promptTokensDetails { fields["prompt_tokens_details"] = .object(promptTokensDetails.fields) }
        if let completionTokensDetails { fields["completion_tokens_details"] = .object(completionTokensDetails.fields) }
        return fields
    }
    public func encode(to encoder: Encoder) throws { try fields.encode(to: encoder) }
}

public func convertAlibabaUsage(_ usage: AlibabaUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    let input = usage.promptTokens ?? 0
    let output = usage.completionTokens ?? 0
    let read = usage.promptTokensDetails?.cachedTokens ?? 0
    let write = usage.promptTokensDetails?.cacheCreationInputTokens ?? 0
    let reasoning = usage.completionTokensDetails?.reasoningTokens ?? 0
    func difference(_ total: Double, _ first: Double, _ second: Double = 0, clamp: Bool = false) -> Int? {
        if let total = Int(exactly: total), let first = Int(exactly: first), let second = Int(exactly: second) {
            func subtract(_ first: Int, _ second: Int) -> Int? {
                let initial = total.subtractingReportingOverflow(first)
                guard !initial.overflow else { return nil }
                let result = initial.partialValue.subtractingReportingOverflow(second)
                guard !result.overflow else { return nil }
                return clamp ? max(0, result.partialValue) : result.partialValue
            }
            if let result = subtract(first, second) ?? subtract(second, first) { return result }
            return clamp && Double(total) - Double(first) - Double(second) < 0 ? 0 : nil
        }
        let result = total - first - second
        return Int(exactly: clamp ? max(0, result) : result)
    }
    return .init(inputTokens: .init(total: Int(exactly: input), noCache: difference(input, read, write), cacheRead: Int(exactly: read), cacheWrite: Int(exactly: write)),
                 outputTokens: .init(total: Int(exactly: output), text: difference(output, reasoning, clamp: true), reasoning: Int(exactly: reasoning)), raw: .object(usage.fields))
}

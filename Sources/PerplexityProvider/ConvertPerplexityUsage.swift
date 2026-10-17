import Foundation
import AISDKProvider

struct PerplexityUsage: Decodable, Sendable {
    struct InputDetails: Decodable, Sendable {
        let cached: Double?
        let creation: Double?
        let read: Double?
        init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            cached = try value.optional(Double.self, "cached_tokens")
            creation = try value.optional(Double.self, "cache_creation_input_tokens")
            read = try value.optional(Double.self, "cache_read_input_tokens")
        }
    }
    struct OutputDetails: Decodable, Sendable {
        let reasoning: Double?
        init(from decoder: Decoder) throws { reasoning = try PerplexityObject(decoder).optional(Double.self, "reasoning_tokens") }
    }
    struct ToolCall: Decodable, Sendable {
        let invocation: Double?
        init(from decoder: Decoder) throws { invocation = try PerplexityObject(decoder).optional(Double.self, "invocation") }
    }
    struct Cost: Decodable, Sendable {
        let currency: String?
        let input: Double?
        let output: Double?
        let total: Double?
        let creation: Double?
        let read: Double?
        let tools: Double?
        init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            currency = try value.optional(String.self, "currency")
            input = try value.optional(Double.self, "input_cost")
            output = try value.optional(Double.self, "output_cost")
            total = try value.optional(Double.self, "total_cost")
            creation = try value.optional(Double.self, "cache_creation_cost", nullable: true)
            read = try value.optional(Double.self, "cache_read_cost", nullable: true)
            tools = try value.optional(Double.self, "tool_calls_cost", nullable: true)
        }
    }
    let raw: JSONObject
    let input: Int?
    let output: Int?
    let cacheRead: Int?
    let cacheWrite: Int?
    let reasoning: Int?
    let noCache: Int?
    let text: Int?
    let toolCalls: [String: ToolCall]?
    let cost: Cost?

    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        raw = value.fields
        let inputValue = try value.required(Double.self, "input_tokens")
        let outputValue = try value.required(Double.self, "output_tokens")
        _ = try value.required(Double.self, "total_tokens")
        let details = try value.optional(InputDetails.self, "input_tokens_details", nullable: true)
        let outputDetails = try value.optional(OutputDetails.self, "output_tokens_details", nullable: true)
        toolCalls = try value.optional([String: ToolCall].self, "tool_calls_details", nullable: true)
        cost = try value.optional(Cost.self, "cost", nullable: true)
        let read = details?.read ?? details?.cached ?? 0
        let write = details?.creation ?? 0
        let reasoningValue = outputDetails?.reasoning ?? 0
        func difference(_ total: Double, _ first: Double, _ second: Double = 0) -> Int? {
            let rawDifference = total - first - second
            if let total = Int(exactly: total), let first = Int(exactly: first), let second = Int(exactly: second) {
                func subtract(_ first: Int, _ second: Int) -> Int? {
                    let intermediate = total.subtractingReportingOverflow(first)
                    guard !intermediate.overflow else { return nil }
                    let result = intermediate.partialValue.subtractingReportingOverflow(second)
                    return result.overflow ? nil : max(0, result.partialValue)
                }
                if let value = subtract(first, second) ?? subtract(second, first) { return value }
                return rawDifference < 0 ? 0 : nil
            }
            return Int(exactly: max(0, rawDifference))
        }
        input = Int(exactly: inputValue)
        output = Int(exactly: outputValue)
        cacheRead = Int(exactly: read)
        cacheWrite = Int(exactly: write)
        reasoning = Int(exactly: reasoningValue)
        noCache = difference(inputValue, read, write)
        text = difference(outputValue, reasoningValue)
    }
}

func convertPerplexityUsage(_ usage: PerplexityUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    return .init(inputTokens: .init(total: usage.input, noCache: usage.noCache, cacheRead: usage.cacheRead, cacheWrite: usage.cacheWrite),
                 outputTokens: .init(total: usage.output, text: usage.text, reasoning: usage.reasoning), raw: .object(usage.raw))
}

func perplexityProviderMetadata(_ usage: PerplexityUsage?) -> SharedV4ProviderMetadata {
    let cost: JSONValue
    if let value = usage?.cost {
        cost = ["inputTokensCost": value.input.map(JSONValue.number) ?? .null,
                "outputTokensCost": value.output.map(JSONValue.number) ?? .null, "requestCost": .null,
                "totalCost": value.total.map(JSONValue.number) ?? .null, "currency": value.currency.map(JSONValue.string) ?? .null,
                "cacheCreationCost": value.creation.map(JSONValue.number) ?? .null, "cacheReadCost": value.read.map(JSONValue.number) ?? .null,
                "toolCallsCost": value.tools.map(JSONValue.number) ?? .null]
    } else { cost = .null }
    let calls: JSONValue
    let queries: JSONValue
    if let details = usage?.toolCalls {
        calls = .object(details.mapValues { .object(["invocation": $0.invocation.map(JSONValue.number) ?? .null]) })
        queries = .number(details.filter { $0.key.contains("search") }.reduce(0) { $0 + ($1.value.invocation ?? 0) })
    } else { calls = .null; queries = .null }
    return ["perplexity": ["images": .null, "usage": ["citationTokens": .null, "numSearchQueries": queries], "cost": cost, "toolCalls": calls]]
}

import Foundation
import AISDKProvider

struct CohereUsage: Decodable, Sendable {
    let raw: JSONValue
    let input: Int?
    let output: Int?
    let cached: Int?
    let noCache: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        raw = try container.decode(JSONValue.self)
        guard case .object(let fields) = raw, case .object(let tokens) = fields["tokens"] else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected Cohere usage tokens object")
        }
        func number(_ value: JSONValue?, name: String) throws -> Double {
            guard case .number(let value) = value, value.isFinite else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected finite number for \(name)")
            }
            return value
        }
        let inputValue = try number(tokens["input_tokens"], name: "input_tokens")
        let outputValue = try number(tokens["output_tokens"], name: "output_tokens")
        input = Int(exactly: inputValue)
        output = Int(exactly: outputValue)
        if let billed = fields["billed_units"], billed != .null {
            guard case .object(let units) = billed else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected billed_units object")
            }
            _ = try number(units["input_tokens"], name: "billed_units.input_tokens")
            _ = try number(units["output_tokens"], name: "billed_units.output_tokens")
        }
        if let value = fields["cached_tokens"], value != .null {
            let cachedValue = try number(value, name: "cached_tokens")
            cached = Int(exactly: cachedValue)
            if let input, let cached {
                let subtraction = input.subtractingReportingOverflow(cached)
                noCache = subtraction.overflow ? nil : subtraction.partialValue
            } else { noCache = Int(exactly: inputValue - cachedValue) }
        } else {
            cached = nil
            noCache = input
        }
    }
}

func convertCohereUsage(_ usage: CohereUsage?) -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    return .init(
        inputTokens: .init(total: usage.input, noCache: usage.noCache, cacheRead: usage.cached),
        outputTokens: .init(total: usage.output, text: usage.output),
        raw: usage.raw
    )
}

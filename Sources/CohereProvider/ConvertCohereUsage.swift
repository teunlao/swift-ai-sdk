import Foundation
import AISDKProvider

struct CohereUsage: Decodable, Sendable {
    let raw: JSONValue
    let input: Int
    let output: Int
    let cached: Int?
    let noCache: Int

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
        func count(_ value: Double, name: String) throws -> Int {
            guard let count = Int(exactly: value) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected representable integer for \(name)")
            }
            return count
        }
        input = try count(number(tokens["input_tokens"], name: "input_tokens"), name: "input_tokens")
        output = try count(number(tokens["output_tokens"], name: "output_tokens"), name: "output_tokens")
        if let billed = fields["billed_units"], billed != .null {
            guard case .object(let units) = billed else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected billed_units object")
            }
            _ = try number(units["input_tokens"], name: "billed_units.input_tokens")
            _ = try number(units["output_tokens"], name: "billed_units.output_tokens")
        }
        if let value = fields["cached_tokens"], value != .null {
            cached = try count(number(value, name: "cached_tokens"), name: "cached_tokens")
        } else { cached = nil }
        let subtraction = input.subtractingReportingOverflow(cached ?? 0)
        guard !subtraction.overflow else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Uncached token count exceeds the supported integer range")
        }
        noCache = subtraction.partialValue
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

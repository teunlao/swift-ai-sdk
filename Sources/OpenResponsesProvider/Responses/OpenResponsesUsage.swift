import AISDKProvider

struct OpenResponsesUsage: Sendable {
    let raw: JSONValue
    let input: Int?
    let output: Int?
    let cached: Int?
    let written: Int?
    let reasoning: Int?
    let noCache: Int?
    let text: Int?

    init(_ raw: JSONValue) throws {
        guard case .object(let fields) = raw else { throw InvalidResponseDataError(data: raw, message: "Expected response usage object") }
        self.raw = raw
        func number(_ value: JSONValue?) throws -> Double? {
            guard let value, value != .null else { return nil }
            guard case .number(let number) = value else {
                throw InvalidResponseDataError(data: value, message: "Expected numeric token count")
            }
            return number
        }
        let inputDetails = openResponsesObject(fields["input_tokens_details"])
        let outputDetails = openResponsesObject(fields["output_tokens_details"])
        let inputValue = try number(fields["input_tokens"])
        let outputValue = try number(fields["output_tokens"])
        let cachedValue = try number(inputDetails?["cached_tokens"])
        let writtenValue = try number(inputDetails?["cache_write_tokens"])
        let reasoningValue = try number(outputDetails?["reasoning_tokens"])
        input = inputValue.flatMap { Int(exactly: $0) }
        output = outputValue.flatMap { Int(exactly: $0) }
        cached = cachedValue.flatMap { Int(exactly: $0) }
        written = writtenValue.flatMap { Int(exactly: $0) }
        reasoning = reasoningValue.flatMap { Int(exactly: $0) }
        func difference(_ total: Double, _ first: Double, _ second: Double = 0) -> Int? {
            if let total = Int(exactly: total), let first = Int(exactly: first), let second = Int(exactly: second) {
                func subtract(_ first: Int, _ second: Int) -> Int? {
                    let intermediate = total.subtractingReportingOverflow(first)
                    guard !intermediate.overflow else { return nil }
                    let result = intermediate.partialValue.subtractingReportingOverflow(second)
                    return result.overflow ? nil : result.partialValue
                }
                return subtract(first, second) ?? subtract(second, first)
            }
            return Int(exactly: total - first - second)
        }
        noCache = difference(inputValue ?? 0, cachedValue ?? 0, writtenValue ?? 0)
        text = difference(outputValue ?? 0, reasoningValue ?? 0)
    }
    var value: LanguageModelV4Usage {
        .init(inputTokens: .init(total: input, noCache: noCache, cacheRead: cached, cacheWrite: written),
              outputTokens: .init(total: output, text: text, reasoning: reasoning), raw: raw)
    }
}

func openResponsesGenerationUsage(_ usage: OpenResponsesUsage?) -> LanguageModelV4Usage {
    usage?.value ?? .init(inputTokens: .init(noCache: 0), outputTokens: .init(text: 0))
}

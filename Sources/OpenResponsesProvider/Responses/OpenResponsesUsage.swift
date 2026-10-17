import AISDKProvider

struct OpenResponsesUsage: Sendable {
    let raw: JSONValue
    let input: Int?
    let output: Int?
    let cached: Int?
    let written: Int?
    let reasoning: Int?
    let noCache: Int
    let text: Int

    init(_ raw: JSONValue) throws {
        guard case .object(let fields) = raw else { throw InvalidResponseDataError(data: raw, message: "Expected response usage object") }
        self.raw = raw
        func count(_ value: JSONValue?) throws -> Int? {
            guard let value, value != .null else { return nil }
            guard case .number(let number) = value, let count = Int(exactly: number) else {
                throw InvalidResponseDataError(data: value, message: "Expected representable token count")
            }
            return count
        }
        let inputDetails = openResponsesObject(fields["input_tokens_details"])
        let outputDetails = openResponsesObject(fields["output_tokens_details"])
        input = try count(fields["input_tokens"])
        output = try count(fields["output_tokens"])
        cached = try count(inputDetails?["cached_tokens"])
        written = try count(inputDetails?["cache_write_tokens"])
        reasoning = try count(outputDetails?["reasoning_tokens"])
        func difference(_ value: Double) throws -> Int {
            guard let result = Int(exactly: value) else { throw InvalidResponseDataError(data: raw, message: "Derived token count exceeds the supported integer range") }
            return result
        }
        noCache = try difference(Double(input ?? 0) - Double(cached ?? 0) - Double(written ?? 0))
        text = try difference(Double(output ?? 0) - Double(reasoning ?? 0))
    }
    var value: LanguageModelV4Usage {
        .init(inputTokens: .init(total: input, noCache: noCache, cacheRead: cached, cacheWrite: written),
              outputTokens: .init(total: output, text: text, reasoning: reasoning), raw: raw)
    }
}

func openResponsesGenerationUsage(_ usage: OpenResponsesUsage?) -> LanguageModelV4Usage {
    usage?.value ?? .init(inputTokens: .init(noCache: 0), outputTokens: .init(text: 0))
}

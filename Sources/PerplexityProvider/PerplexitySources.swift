import AISDKProvider
import AISDKProviderUtils

struct PerplexitySource {
    let id: String
    let url: String
    let title: String?
    let metadata: SharedV4ProviderMetadata?
    let resultId: Double?

    init(annotation: PerplexityContentPart.Annotation, url: String, generateId: IDGenerator) {
        id = generateId()
        self.url = url
        title = annotation.title
        metadata = nil
        resultId = nil
    }
    init(result: PerplexitySearchResult, generateId: IDGenerator) throws {
        id = try result.id.map(perplexityNumberString) ?? generateId()
        url = result.url
        title = result.title
        resultId = result.id
        metadata = ["perplexity": ["resultId": result.id.map(JSONValue.number) ?? .null,
                                   "snippet": result.snippet.map(JSONValue.string) ?? .null,
                                   "date": result.date.map(JSONValue.string) ?? .null,
                                   "lastUpdated": result.lastUpdated.map(JSONValue.string) ?? .null,
                                   "source": result.source.map(JSONValue.string) ?? .null]]
    }
    init(fetched: PerplexityFetchedContent, generateId: IDGenerator) {
        id = generateId()
        url = fetched.url
        title = fetched.title
        resultId = nil
        metadata = ["perplexity": ["snippet": fetched.snippet.map(JSONValue.string) ?? .null]]
    }
    var value: LanguageModelV4Source { .url(id: id, url: url, title: title, providerMetadata: metadata) }
}

func perplexityOutputSources(_ item: PerplexityOutputItem, generateId: IDGenerator) throws -> [PerplexitySource] {
    switch item {
    case .message(_, let content):
        var sources: [PerplexitySource] = []
        for part in content ?? [] {
            for annotation in part.annotations ?? [] {
                if let url = annotation.url { sources.append(.init(annotation: annotation, url: url, generateId: generateId)) }
            }
        }
        return sources
    case .searchResults(let results): return try (results ?? []).map { try .init(result: $0, generateId: generateId) }
    case .fetchedContents(let contents): return (contents ?? []).map { .init(fetched: $0, generateId: generateId) }
    case .functionCall, .unhandled: return []
    }
}

func perplexityToolCall(_ call: PerplexityOutputItem.FunctionCall) -> LanguageModelV4ToolCall? {
    guard let id = call.callId, let name = call.name, let arguments = call.arguments else { return nil }
    var metadata: JSONObject = ["itemId": call.id.map(JSONValue.string) ?? .null]
    if let signature = call.thoughtSignature { metadata["thoughtSignature"] = .string(signature) }
    return .init(toolCallId: id, toolName: name, input: arguments, providerMetadata: ["perplexity": metadata])
}

func perplexityNumberString(_ value: Double) throws -> String {
    if value == 0 { return "0" }
    // Agent identifiers follow ECMAScript's decimal and exponent thresholds.
    let encoded = try perplexityJSONString(value).lowercased()
    let negative = encoded.hasPrefix("-")
    let magnitude = negative ? encoded.dropFirst() : encoded[...]
    let components = magnitude.split(separator: "e", maxSplits: 1)
    let exponent: Int
    if components.count == 2 {
        guard let parsed = Int(components[1]) else {
            throw InvalidResponseDataError(data: encoded, message: "Invalid numeric identifier exponent")
        }
        exponent = parsed
    } else { exponent = 0 }
    let mantissa = components[0]
    let integerDigits = mantissa.prefix { $0 != "." }.count
    let rawDigits = mantissa.filter { $0 != "." }
    let leadingZeros = rawDigits.prefix { $0 == "0" }.count
    var digits = rawDigits.dropFirst(leadingZeros)
    while digits.last == "0" { digits = digits.dropLast() }
    let significand = String(digits)
    let position = integerDigits + exponent - leadingZeros
    let scientificExponent = position - 1
    let sign = negative ? "-" : ""
    if scientificExponent >= -6 && scientificExponent < 21 {
        if position <= 0 { return sign + "0." + String(repeating: "0", count: -position) + significand }
        if position >= significand.count { return sign + significand + String(repeating: "0", count: position - significand.count) }
        let point = significand.index(significand.startIndex, offsetBy: position)
        return sign + significand[..<point] + "." + significand[point...]
    }
    let tail = significand.dropFirst()
    let coefficient = String(significand.prefix(1)) + (tail.isEmpty ? "" : "." + tail)
    return sign + coefficient + "e" + (scientificExponent >= 0 ? "+" : "") + String(scientificExponent)
}

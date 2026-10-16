import Foundation
import AISDKProvider
import AISDKProviderUtils

struct ProdiaModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () async throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

struct ProdiaJobResult: Decodable, Sendable {
    struct Config: Decodable, Sendable { let seed: Double? }
    struct Metrics: Decodable, Sendable { let elapsed: Double?; let ips: Double? }
    struct Price: Decodable, Sendable { let product: String; let dollars: Double }
    struct State: Decodable, Sendable { let current: String }
    let id: String
    let created_at: String?
    let updated_at: String?
    let expires_at: String?
    let state: State?
    let config: Config?
    let metrics: Metrics?
    let price: Price?

    var metadata: [String: JSONValue] {
        var result: [String: JSONValue] = ["jobId": .string(id)]
        if let seed = config?.seed { result["seed"] = .number(seed) }
        if let elapsed = metrics?.elapsed { result["elapsed"] = .number(elapsed) }
        if let ips = metrics?.ips { result["iterationsPerSecond"] = .number(ips) }
        if let created_at { result["createdAt"] = .string(created_at) }
        if let updated_at { result["updatedAt"] = .string(updated_at) }
        if let dollars = price?.dollars { result["dollars"] = .number(dollars) }
        return result
    }
}

private let prodiaJobSchema = FlexibleSchema(jsonSchema(.object([
    "type": .string("object"), "required": .array([.string("id")]), "properties": .object([
        "id": .object(["type": .string("string")]),
        "created_at": .object(["type": .string("string")]), "updated_at": .object(["type": .string("string")]), "expires_at": .object(["type": .string("string")]),
        "state": .object(["type": .string("object"), "required": .array([.string("current")]), "properties": .object(["current": .object(["type": .string("string")])])]),
        "config": .object(["type": .string("object"), "properties": .object(["seed": .object(["type": .string("number")])])]),
        "metrics": .object(["type": .string("object"), "properties": .object(["elapsed": .object(["type": .string("number")]), "ips": .object(["type": .string("number")])])]),
        "price": .object(["type": .array([.string("object"), .string("null")]), "required": .array([.string("product"), .string("dollars")]), "properties": .object(["product": .object(["type": .string("string")]), "dollars": .object(["type": .string("number")])])])
    ])
])))

private struct ProdiaError: Decodable, Sendable {
    let message: String?
    let detail: JSONValue?
    let error: String?
    private enum CodingKeys: String, CodingKey { case message, detail, error }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        message = values.contains(.message) ? try values.decode(String.self, forKey: .message) : nil
        detail = try values.decodeIfPresent(JSONValue.self, forKey: .detail)
        error = values.contains(.error) ? try values.decode(String.self, forKey: .error) : nil
    }
}

let prodiaFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: FlexibleSchema(Schema<ProdiaError>.codable(ProdiaError.self, jsonSchema: .object(["type": .string("object")]))),
    errorToMessage: { payload in
        if let detail = payload.detail, detail != .null {
            if case .string(let value) = detail { return value }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
            if let encoded = try? encoder.encode(detail), let value = String(data: encoded, encoding: .utf8) { return value }
        }
        return payload.error ?? payload.message ?? "Unknown Prodia error"
    }
)

struct ProdiaMultipartPart: Sendable {
    let headers: [String: String]
    let body: Data
    var disposition: String { headers["content-disposition"] ?? "" }
    var mediaType: String { headers["content-type"] ?? "" }
}

struct ProdiaMultipartResponse: Sendable {
    let job: ProdiaJobResult
    let parts: [ProdiaMultipartPart]
}

let prodiaMultipartResponseHandler: ResponseHandler<ProdiaMultipartResponse> = { input in
    let response = input.response
    let contentType = response.httpResponse.value(forHTTPHeaderField: "content-type") ?? ""
    guard let range = contentType.range(of: "boundary="),
          let token = contentType[range.upperBound...].split(whereSeparator: { $0.isWhitespace || $0 == ";" }).first else {
        throw InvalidResponseDataError(data: contentType, message: "Prodia response missing multipart boundary in content-type: \(contentType)")
    }
    let parts = parseProdiaMultipart(try await response.body.collectData(), boundary: String(token))
    var job: ProdiaJobResult?
    for part in parts where part.disposition.contains("name=\"job\"") {
        let value = try await parseJSON(ParseJSONWithSchemaOptions(text: String(decoding: part.body, as: UTF8.self), schema: prodiaJobSchema))
        job = try JSONDecoder().decode(ProdiaJobResult.self, from: JSONEncoder().encode(value))
    }
    guard let job else { throw InvalidResponseDataError(data: nil, message: "Prodia multipart response missing job part") }
    return .init(value: .init(job: job, parts: parts), responseHeaders: extractResponseHeaders(from: response.httpResponse))
}

private func parseProdiaMultipart(_ data: Data, boundary: String) -> [ProdiaMultipartPart] {
    let marker = Data("--\(boundary)".utf8)
    var boundaries: [Range<Int>] = []
    var start = 0
    while start < data.count, let range = data.range(of: marker, in: start..<data.count) {
        boundaries.append(range)
        start = range.upperBound
    }
    var parts: [ProdiaMultipartPart] = []
    for (current, next) in zip(boundaries, boundaries.dropFirst()) {
        var start = current.upperBound
        var end = next.lowerBound
        if start + 1 < end, data[start] == 13, data[start + 1] == 10 { start += 2 }
        else if start < end, data[start] == 10 { start += 1 }
        if end - 2 >= start, data[end - 2] == 13, data[end - 1] == 10 { end -= 2 }
        else if end - 1 >= start, data[end - 1] == 10 { end -= 1 }
        guard start < end else { continue }
        let crlf = data.range(of: Data([13, 10, 13, 10]), in: start..<end)
        let lf = data.range(of: Data([10, 10]), in: start..<end)
        guard let separator = [crlf, lf].compactMap({ $0 }).min(by: { $0.lowerBound < $1.lowerBound }) else { continue }
        let text = String(decoding: data.subdata(in: start..<separator.lowerBound), as: UTF8.self)
        var headers: [String: String] = [:]
        for line in text.components(separatedBy: .newlines) {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[key] = value
        }
        parts.append(.init(headers: headers, body: data.subdata(in: separator.upperBound..<end)))
    }
    return parts
}

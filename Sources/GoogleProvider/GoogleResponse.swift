import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias GroundingMetadataSchema = JSONValue
public typealias UrlContextMetadataSchema = JSONValue
public typealias SafetyRatingSchema = JSONValue

struct GoogleResponse: Codable, Sendable {
    struct Candidate: Codable, Sendable {
        struct Content: Codable, Sendable { let parts: [Part]? }
        let content: Content?
        let finishReason: String?
        let finishMessage: String?
        let continuationToken: String?
        let safetyRatings: JSONValue?
        let groundingMetadata: JSONValue?
        let urlContextMetadata: JSONValue?
    }
    struct Part: Codable, Sendable {
        struct InlineData: Codable, Sendable { let mimeType: String; let data: String }
        struct FunctionCall: Codable, Sendable {
            let id: String?
            let name: String?
            let args: JSONValue?
            let partialArgs: [GooglePartialArg]?
            let willContinue: Bool?
        }
        struct ServerCall: Codable, Sendable { let id: String; let toolType: String; let args: JSONValue? }
        struct ServerResponse: Codable, Sendable { let id: String; let toolType: String; let response: JSONValue? }
        struct Code: Codable, Sendable { let language: String?; let code: String? }
        struct CodeResult: Codable, Sendable { let outcome: String?; let output: String? }
        let text: String?
        let thought: Bool?
        let thoughtSignature: String?
        let inlineData: InlineData?
        let functionCall: FunctionCall?
        let executableCode: Code?
        let codeExecutionResult: CodeResult?
        let toolCall: ServerCall?
        let toolResponse: ServerResponse?
    }
    let responseId: String?
    let candidates: [Candidate]?
    let usageMetadata: [String: JSONValue]?
    let promptFeedback: JSONValue?
}

let googleResponseSchema = FlexibleSchema(Schema<GoogleResponse>(jsonSchemaResolver: { googleResponseWire.jsonSchema }, validator: { value in
    do {
        let projected = try googleResponseWire.parse(jsonValue(from: value))
        return .success(value: try JSONDecoder().decode(GoogleResponse.self, from: JSONEncoder().encode(projected)))
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

func googleTokenCount(_ value: Double?) throws -> Int? {
    guard let value else { return nil }
    guard let count = Int(exactly: value) else {
        throw InvalidResponseDataError(data: value, message: "Token count cannot be represented by the native integer usage contract")
    }
    return count
}

func convertGoogleUsage(_ usage: [String: JSONValue]?) throws -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    func count(_ key: String) -> Double {
        guard case .number(let value) = usage[key] else { return 0 }
        return value
    }
    let input = count("promptTokenCount") + count("toolUsePromptTokenCount")
    let cached = count("cachedContentTokenCount")
    let output = count("candidatesTokenCount")
    let thoughts = count("thoughtsTokenCount")
    return try .init(inputTokens: .init(total: googleTokenCount(input), noCache: googleTokenCount(input - cached), cacheRead: googleTokenCount(cached)), outputTokens: .init(total: googleTokenCount(output + thoughts), text: googleTokenCount(output), reasoning: googleTokenCount(thoughts)), raw: .object(usage))
}

func addGoogleUsage(_ first: [String: JSONValue]?, _ second: [String: JSONValue]?) -> [String: JSONValue]? {
    guard let first else { return second }
    guard let second else { return first }
    var result = first.merging(second) { _, value in value }
    for key in ["promptTokenCount", "candidatesTokenCount", "toolUsePromptTokenCount", "totalTokenCount", "cachedContentTokenCount", "thoughtsTokenCount"] {
        if case .number(let a) = first[key] {
            let b: Double
            if case .number(let value) = second[key] { b = value } else { b = 0 }
            result[key] = .number(a + b)
        }
    }
    for key in ["promptTokensDetails", "cacheTokensDetails", "candidatesTokensDetails", "toolUsePromptTokensDetails"] {
        guard case .array(let a) = first[key], case .array(let b) = second[key] else { continue }
        var order: [String] = []
        var counts: [String: Double] = [:]
        for detail in a + b {
            guard case .object(let object) = detail, case .string(let modality) = object["modality"], case .number(let count) = object["tokenCount"] else { continue }
            if counts[modality] == nil { order.append(modality) }
            counts[modality, default: 0] += count
        }
        result[key] = .array(order.map { .object(["modality": .string($0), "tokenCount": .number(counts[$0]!)]) })
    }
    return result
}

func googlePromptBlockReason(_ feedback: JSONValue?) -> String? {
    guard case .object(let object) = feedback, case .string(let reason) = object["blockReason"],
          !["", "BLOCK_REASON_UNSPECIFIED", "BLOCKED_REASON_UNSPECIFIED"].contains(reason) else { return nil }
    return reason
}

func googleThoughtMetadata(_ signature: String?, names: [String]) -> SharedV4ProviderMetadata? {
    guard let signature, !signature.isEmpty else { return nil }
    return googleProviderMetadata(["thoughtSignature": .string(signature)], names: names)
}

func googleServerMetadata(id: String, type: String, signature: String?, names: [String]) -> SharedV4ProviderMetadata {
    var payload: [String: JSONValue] = ["serverToolCallId": .string(id), "serverToolType": .string(type)]
    if let signature, !signature.isEmpty { payload["thoughtSignature"] = .string(signature) }
    return googleProviderMetadata(payload, names: names)
}

func googleResponseMetadata(response: GoogleResponse, usage: [String: JSONValue]?, names: [String], initialPromptTokens: JSONValue? = nil) -> SharedV4ProviderMetadata {
    let candidate = response.candidates?.first
    var metadata: [String: JSONValue] = [
        "promptFeedback": response.promptFeedback ?? .null,
        "groundingMetadata": candidate?.groundingMetadata ?? .null,
        "urlContextMetadata": candidate?.urlContextMetadata ?? .null,
        "safetyRatings": candidate?.safetyRatings ?? .null,
        "usageMetadata": usage.map(JSONValue.object) ?? .null,
        "finishMessage": candidate?.finishMessage.map(JSONValue.string) ?? .null,
        "serviceTier": usage?["serviceTier"] ?? .null
    ]
    if let token = candidate?.continuationToken { metadata["continuationToken"] = .string(token) }
    if let initialPromptTokens { metadata["initialPromptTokenCount"] = initialPromptTokens }
    return googleProviderMetadata(metadata, names: names)
}

func googleSources(_ grounding: JSONValue?, generateId: @Sendable () -> String) -> [LanguageModelV4Source] {
    guard case .object(let metadata) = grounding, case .array(let chunks) = metadata["groundingChunks"] else { return [] }
    var result: [LanguageModelV4Source] = []
    for chunk in chunks {
        guard case .object(let object) = chunk else { continue }
        func string(_ value: JSONValue?) -> String? { if case .string(let text) = value { return text }; return nil }
        if case .object(let web) = object["web"], let uri = string(web["uri"]) {
            result.append(.url(id: generateId(), url: uri, title: string(web["title"]), providerMetadata: nil))
        } else if case .object(let image) = object["image"], let uri = string(image["sourceUri"]) {
            result.append(.url(id: generateId(), url: uri, title: string(image["title"]), providerMetadata: nil))
        } else if case .object(let context) = object["retrievedContext"] {
            let uri = string(context["uri"]).flatMap { $0.isEmpty ? nil : $0 }
            if let uri, uri.hasPrefix("https://") || uri.hasPrefix("http://") {
                result.append(.url(id: generateId(), url: uri, title: string(context["title"]), providerMetadata: nil))
            } else if let path = uri ?? string(context["fileSearchStore"]).flatMap({ $0.isEmpty ? nil : $0 }) {
                let types = ["pdf": "application/pdf", "txt": "text/plain", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "doc": "application/msword", "md": "text/markdown", "markdown": "text/markdown"]
                let ext = path.components(separatedBy: ".").last ?? ""
                result.append(.document(id: generateId(), mediaType: uri == nil ? "application/octet-stream" : types[ext] ?? "application/octet-stream", title: string(context["title"]) ?? "Unknown Document", filename: path.components(separatedBy: "/").last, providerMetadata: nil))
            }
        } else if case .object(let maps) = object["maps"], let uri = string(maps["uri"]), !uri.isEmpty {
            result.append(.url(id: generateId(), url: uri, title: string(maps["title"]), providerMetadata: nil))
        }
    }
    return result
}

func encodeGooglePrompt(_ prompt: GooglePrompt) -> (system: JSONValue?, contents: JSONValue) {
    let system = prompt.systemInstruction.map { JSONValue.object(["parts": .array($0.parts.map { .object(["text": .string($0.text)]) })]) }
    let contents = prompt.contents.map { content -> JSONValue in
        let parts = content.parts.map { part -> JSONValue in
            switch part {
            case .raw(let value): return value
            case .text(let part):
                var object: [String: JSONValue] = ["text": .string(part.text)]
                if let thought = part.thought { object["thought"] = .bool(thought) }
                if let signature = part.thoughtSignature { object["thoughtSignature"] = .string(signature) }
                return .object(object)
            case .inlineData(let part):
                var object: [String: JSONValue] = ["inlineData": .object(["mimeType": .string(part.mimeType), "data": .string(part.data)])]
                if let thought = part.thought { object["thought"] = .bool(thought) }
                if let signature = part.thoughtSignature { object["thoughtSignature"] = .string(signature) }
                return .object(object)
            case .fileData(let part): return .object(["fileData": .object(["mimeType": .string(part.mimeType), "fileUri": .string(part.fileURI)])])
            case .functionCall(let part):
                var call: [String: JSONValue] = ["name": .string(part.name), "args": part.arguments]
                if let id = part.id { call["id"] = .string(id) }
                var object: [String: JSONValue] = ["functionCall": .object(call)]
                if let signature = part.thoughtSignature { object["thoughtSignature"] = .string(signature) }
                return .object(object)
            case .functionResponse(let part):
                var response: [String: JSONValue] = ["name": .string(part.name), "response": part.response]
                if let id = part.id { response["id"] = .string(id) }
                if let parts = part.parts, !parts.isEmpty { response["parts"] = .array(parts.map { .object(["inlineData": .object(["mimeType": .string($0.inlineData.mimeType), "data": .string($0.inlineData.data)])]) }) }
                return .object(["functionResponse": .object(response)])
            }
        }
        return .object(["role": .string(content.role.rawValue), "parts": .array(parts)])
    }
    return (system, .array(contents))
}

public func getGroundingMetadataSchema() -> Schema<JSONValue> { googleGroundingWire.schema }
public func getUrlContextMetadataSchema() -> Schema<JSONValue> { googleUrlContextWire.schema }

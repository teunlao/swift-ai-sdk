import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleInteractionsProviderMetadata: Sendable, Codable, Equatable {
    public let interactionId: String?
    public let serviceTier: String?
    public let outputTokensByModality: [String: Double]?
    public let signature: String?
    public let processingId: String?
    public let processingCallId: String?
    public init(interactionId: String? = nil, serviceTier: String? = nil, outputTokensByModality: [String: Double]? = nil, signature: String? = nil, processingId: String? = nil, processingCallId: String? = nil) {
        self.interactionId = interactionId; self.serviceTier = serviceTier; self.outputTokensByModality = outputTokensByModality
        self.signature = signature; self.processingId = processingId; self.processingCallId = processingCallId
    }
}

struct GoogleInteractionResponse: Codable, Sendable {
    let id: String?
    let created: String?
    let status: String
    let model: String?
    let steps: [JSONObject]?
    let usage: JSONObject?
    let service_tier: String?
    private let raw: JSONObject
    private enum CodingKeys: String, CodingKey { case id, created, status, model, steps, usage, service_tier }
    init(from decoder: Decoder) throws {
        raw = try JSONObject(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
        created = try container.decodeIfPresent(String.self, forKey: .created)
        status = try container.decode(String.self, forKey: .status)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        steps = try container.decodeIfPresent([JSONObject].self, forKey: .steps)
        usage = try container.decodeIfPresent(JSONObject.self, forKey: .usage)
        service_tier = try container.decodeIfPresent(String.self, forKey: .service_tier)
    }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}
struct GoogleInteractionEvent: Codable, Sendable {
    private let raw: JSONObject
    let event_type: String
    var event_id: String? { interactionString(raw["event_id"]) }
    var index: Double? { interactionDouble(raw["index"]) }
    var step: JSONObject? { interactionObject(raw["step"]) }
    var delta: JSONObject? { interactionObject(raw["delta"]) }
    var interaction: JSONObject? { interactionObject(raw["interaction"]) }
    var status: String? { interactionString(raw["status"]) }
    var error: JSONObject? { interactionObject(raw["error"]) }
    init(from decoder: Decoder) throws {
        raw = try JSONObject(from: decoder)
        guard let type = interactionString(raw["event_type"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "event_type must be a string"))
        }
        event_type = type
    }
    func encode(to encoder: Encoder) throws { try raw.encode(to: encoder) }
}
let googleInteractionResponseSchema = FlexibleSchema(Schema<GoogleInteractionResponse>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let response = try JSONDecoder().decode(GoogleInteractionResponse.self, from: JSONEncoder().encode(jsonValue(from: value)))
        guard ["in_progress", "requires_action", "completed", "failed", "cancelled", "incomplete"].contains(response.status) else { throw SchemaValidationIssuesError(vendor: "google", issues: "invalid interaction status") }
        if let usage = response.usage { try validateInteractionUsage(usage) }
        for step in response.steps ?? [] {
            guard case .string = step["type"] else { throw SchemaValidationIssuesError(vendor: "google", issues: "interaction step type must be a string") }
        }
        return .success(value: response)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))
let googleInteractionEventSchema = FlexibleSchema(Schema<GoogleInteractionEvent>.codable(GoogleInteractionEvent.self, jsonSchema: .object(["type": .string("object")])))

func interactionString(_ value: JSONValue?) -> String? { if case .string(let value) = value { return value }; return nil }
func interactionObject(_ value: JSONValue?) -> JSONObject? { if case .object(let value) = value { return value }; return nil }
func interactionArray(_ value: JSONValue?) -> [JSONValue] { if case .array(let value) = value { return value }; return [] }
func interactionDouble(_ value: JSONValue?) -> Double? { if case .number(let value) = value { return value }; return nil }
private let interactionUsageWire = GoogleWireSchema.object(optional: [
    "total_input_tokens": .tokenCount, "total_output_tokens": .tokenCount, "total_thought_tokens": .tokenCount,
    "total_cached_tokens": .tokenCount, "total_tool_use_tokens": .tokenCount, "total_tokens": .tokenCount,
    "input_tokens_by_modality": .array(.object(optional: ["modality": .string, "tokens": .number], loose: true)),
    "output_tokens_by_modality": .array(.object(optional: ["modality": .string, "tokens": .number], loose: true)),
    "cached_tokens_by_modality": .array(.object(optional: ["modality": .string, "tokens": .number], loose: true)),
    "tool_use_tokens_by_modality": .array(.object(optional: ["modality": .string, "tokens": .number], loose: true)),
    "grounding_tool_count": .array(.object(optional: ["type": .string, "count": .number], loose: true))
], loose: true)
func validateInteractionUsage(_ usage: JSONObject) throws { _ = try interactionUsageWire.parse(.object(usage)) }
func interactionDate(_ value: String?) -> Date? { value.flatMap { ISO8601DateFormatter().date(from: $0) ?? ISO8601DateFormatter.withFractionalSeconds.date(from: $0) } }
private extension ISO8601DateFormatter {
    static var withFractionalSeconds: ISO8601DateFormatter { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter }
}

func interactionUsage(_ usage: JSONObject?) throws -> LanguageModelV4Usage {
    guard let usage else { return .init() }
    let input = interactionDouble(usage["total_input_tokens"])
    let output = interactionDouble(usage["total_output_tokens"])
    let thought = interactionDouble(usage["total_thought_tokens"])
    let cached = interactionDouble(usage["total_cached_tokens"])
    return try .init(inputTokens: .init(total: googleTokenCount(input), noCache: googleTokenCount(input.map { $0 - (cached ?? 0) }), cacheRead: googleTokenCount(cached)), outputTokens: .init(total: googleTokenCount(output == nil && thought == nil ? nil : (output ?? 0) + (thought ?? 0)), text: googleTokenCount(output), reasoning: googleTokenCount(thought)), raw: .object(usage))
}
func interactionFinish(_ status: String?, functionCall: Bool) -> LanguageModelV4FinishReason {
    let unified: LanguageModelV4FinishReason.Unified
    switch status { case "completed": unified = functionCall ? .toolCalls : .stop; case "requires_action": unified = .toolCalls; case "failed": unified = .error; case "incomplete": unified = .length; default: unified = .other }
    return .init(unified: unified, raw: status)
}
func interactionMetadata(id: String?, tier: String?, usage: JSONObject?, includeModalities: Bool = true) -> SharedV4ProviderMetadata {
    var google: JSONObject = [:]
    if let id, !id.isEmpty { google["interactionId"] = .string(id) }
    if let tier { google["serviceTier"] = .string(tier) }
    if includeModalities {
        var modalities: JSONObject = [:]
        for entry in interactionArray(usage?["output_tokens_by_modality"]) {
            if let object = interactionObject(entry), let modality = interactionString(object["modality"]), case .number = object["tokens"] { modalities[modality] = object["tokens"] }
        }
        if !modalities.isEmpty { google["outputTokensByModality"] = .object(modalities) }
    }
    return ["google": google]
}
func interactionPartMetadata(id: String?, signature: JSONValue? = nil, additional: JSONObject = [:]) -> SharedV4ProviderMetadata? {
    var google = additional
    if let id, !id.isEmpty { google["interactionId"] = .string(id) }
    if let signature, signature != .null { google["signature"] = signature }
    return google.isEmpty ? nil : ["google": google]
}

let interactionBuiltinCalls: Set<String> = ["google_search_call", "code_execution_call", "url_context_call", "file_search_call", "google_maps_call", "mcp_server_tool_call"]
let interactionBuiltinResults: Set<String> = ["google_search_result", "code_execution_result", "url_context_result", "file_search_result", "google_maps_result", "mcp_server_tool_result"]

func parseInteractionOutputs(_ steps: [JSONObject]?, id: String?, generateId: @Sendable () -> String) throws -> (content: [LanguageModelV4Content], functionCall: Bool) {
    var content: [LanguageModelV4Content] = []
    var functionCall = false
    for step in steps ?? [] {
        let type = interactionString(step["type"]) ?? ""
        switch type {
        case "model_output":
            for value in interactionArray(step["content"]) {
                guard let block = interactionObject(value) else { continue }
                let type = interactionString(block["type"])
                if type == "text" {
                    content.append(.text(.init(text: interactionString(block["text"]) ?? "", providerMetadata: interactionPartMetadata(id: id))))
                    content += interactionAnnotationSources(interactionArray(block["annotations"]), generateId: generateId).map(LanguageModelV4Content.source)
                } else if type == "image" || type == "video", let file = try interactionFile(block, id: id) { content.append(.file(file)) }
            }
        case "thought":
            let text = interactionArray(step["summary"]).compactMap { value -> String? in
                guard let object = interactionObject(value), object["type"] == .string("text") else { return nil }; return interactionString(object["text"])
            }.joined(separator: "\n")
            content.append(.reasoning(.init(text: text, providerMetadata: interactionPartMetadata(id: id, signature: step["signature"]))))
        case "function_call":
            functionCall = true
            content.append(.toolCall(.init(toolCallId: interactionString(step["id"]) ?? generateId(), toolName: interactionString(step["name"]) ?? "unknown", input: try googleJSONString(step["arguments"].flatMap { $0 == .null ? nil : $0 } ?? .object([:])), providerMetadata: interactionPartMetadata(id: id, signature: step["signature"]))))
        case "processing_call", "processing_result":
            let key = type == "processing_call" ? "processingId" : "processingCallId"
            content.append(.custom(.init(kind: "google.\(type)", providerMetadata: interactionPartMetadata(id: id, signature: step["signature"], additional: [key: .string(interactionString(step[type == "processing_call" ? "id" : "call_id"]).flatMap { $0.isEmpty ? nil : $0 } ?? generateId())]))))
        default:
            if interactionBuiltinCalls.contains(type) {
                let name = type == "mcp_server_tool_call" ? interactionString(step["name"]) ?? "mcp_server_tool" : String(type.dropLast(5))
                content.append(.toolCall(.init(toolCallId: interactionString(step["id"]).flatMap { $0.isEmpty ? nil : $0 } ?? generateId(), toolName: name, input: try googleJSONString(step["arguments"].flatMap { $0 == .null ? nil : $0 } ?? .object([:])), providerExecuted: true)))
            } else if interactionBuiltinResults.contains(type) {
                let name = type == "mcp_server_tool_result" ? interactionString(step["name"]) ?? "mcp_server_tool" : String(type.dropLast(7))
                content.append(.toolResult(.init(toolCallId: interactionString(step["call_id"]).flatMap { $0.isEmpty ? nil : $0 } ?? generateId(), toolName: name, result: step["result"] ?? .null)))
                content += interactionBuiltinSources(step, generateId: generateId).map(LanguageModelV4Content.source)
            }
        }
    }
    return (content, functionCall)
}

func interactionFile(_ block: JSONObject, id: String?) throws -> LanguageModelV4File? {
    let mediaType = interactionString(block["mime_type"]) ?? (block["type"] == .string("video") ? "video/mp4" : "image/png")
    if let data = interactionString(block["data"]), !data.isEmpty { return .init(mediaType: mediaType, data: .base64(data), providerMetadata: interactionPartMetadata(id: id)) }
    if let uri = interactionString(block["uri"]), !uri.isEmpty {
        guard let url = URL(string: uri), url.scheme != nil else { throw InvalidArgumentError(argument: "uri", message: "Invalid interaction file URL: \(uri)") }
        return .init(mediaType: mediaType, data: .url(url), providerMetadata: interactionPartMetadata(id: id))
    }
    return nil
}

func interactionSourceKey(_ source: LanguageModelV4Source) -> String {
    switch source { case .url(_, let url, _, _): return "url:\(url)"; case .document(_, _, let title, let filename, _): return "doc:\(filename ?? title)" }
}
func interactionAnnotationSources(_ annotations: [JSONValue], generateId: @Sendable () -> String) -> [LanguageModelV4Source] {
    var seen: Set<String> = []
    return annotations.compactMap { value in
        guard let annotation = interactionObject(value), let type = interactionString(annotation["type"]) else { return nil }
        let source: LanguageModelV4Source?
        switch type {
        case "url_citation", "place_citation":
            if let url = interactionString(annotation["url"]), !url.isEmpty { source = .url(id: generateId(), url: url, title: interactionString(annotation[type == "url_citation" ? "title" : "name"]), providerMetadata: nil) } else { source = nil }
        case "file_citation": source = interactionDocumentSource(annotation, citation: true, generateId: generateId)
        default: source = nil
        }
        guard let source, seen.insert(interactionSourceKey(source)).inserted else { return nil }
        return source
    }
}
private func interactionDocumentSource(_ object: JSONObject, citation: Bool, generateId: @Sendable () -> String) -> LanguageModelV4Source? {
    guard let uri = interactionString(object["url"]) ?? interactionString(object["document_uri"]) ?? interactionString(object["file_name"]), !uri.isEmpty else { return nil }
    if uri.hasPrefix("https://") || uri.hasPrefix("http://") { return .url(id: generateId(), url: uri, title: interactionString(object[citation ? "file_name" : "title"]), providerMetadata: nil) }
    let filename = interactionString(object["file_name"]) ?? uri.components(separatedBy: "/").last.flatMap { $0.isEmpty ? nil : $0 }
    let types = ["pdf": "application/pdf", "txt": "text/plain", "md": "text/markdown", "markdown": "text/markdown", "doc": "application/msword", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document"]
    let ext = uri.lowercased().components(separatedBy: ".").last ?? ""
    return .document(id: generateId(), mediaType: types[ext] ?? "application/octet-stream", title: (citation ? nil : interactionString(object["title"])) ?? interactionString(object["file_name"]) ?? filename ?? uri, filename: filename, providerMetadata: nil)
}
func interactionBuiltinSources(_ block: JSONObject, generateId: @Sendable () -> String) -> [LanguageModelV4Source] {
    let type = interactionString(block["type"])
    var sources: [LanguageModelV4Source] = []
    for value in interactionArray(block["result"]) {
        guard let entry = interactionObject(value) else { continue }
        if type == "file_search_result" { if let source = interactionDocumentSource(entry, citation: false, generateId: generateId) { sources.append(source) } }
        else if type == "google_maps_result" {
            for place in interactionArray(entry["places"]).compactMap(interactionObject) {
                if let url = interactionString(place["url"]), !url.isEmpty { sources.append(.url(id: generateId(), url: url, title: interactionString(place["name"]), providerMetadata: nil)) }
            }
        } else if type == "google_search_result" || type == "url_context_result" {
            if type == "url_context_result", let status = interactionString(entry["status"]), status != "success" { continue }
            if let url = interactionString(entry["url"]), !url.isEmpty { sources.append(.url(id: generateId(), url: url, title: type == "google_search_result" ? interactionString(entry["title"]) : nil, providerMetadata: nil)) }
        }
    }
    return sources
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenResponsesAnnotation: Sendable, Equatable {
    let start: Double
    let end: Double
    let url: String
    let title: String
    var fields: JSONObject { ["type": "url_citation", "start_index": .number(start), "end_index": .number(end), "url": .string(url), "title": .string(title)] }

    static func parse(_ value: JSONValue?) -> [Self]? {
        guard case .array(let values) = value else { return nil }
        var result: [Self] = []
        for value in values {
            guard case .object(let item) = value, item["type"] == "url_citation",
                  case .number(let start) = item["start_index"], case .number(let end) = item["end_index"],
                  case .string(let url) = item["url"], case .string(let title) = item["title"] else { return nil }
            result.append(.init(start: start, end: end, url: url, title: title))
        }
        return result
    }
}

struct OpenResponsesTextPart: Sendable {
    let text: String?
    let annotations: [OpenResponsesAnnotation]?
    init(_ fields: JSONObject) {
        text = openResponsesString(fields["text"])
        annotations = OpenResponsesAnnotation.parse(fields["annotations"])
    }
}

struct OpenResponsesReasoningItem: Sendable {
    let id: String?
    let content: [OpenResponsesTextPart]?
    let summary: [OpenResponsesTextPart]?
    let encryptedContent: String?
}
struct OpenResponsesMessageItem: Sendable {
    let id: String?
    let content: [OpenResponsesTextPart]?
}
struct OpenResponsesFunctionItem: Sendable {
    let id: String?
    let callId: String?
    let name: String?
    let arguments: String?
}
struct OpenResponsesCustomItem: Sendable {
    let id: String?
    let callId: String?
    let name: String?
    let input: String?
}

enum OpenResponsesOutputItem: Sendable {
    case reasoning(OpenResponsesReasoningItem)
    case message(OpenResponsesMessageItem)
    case function(OpenResponsesFunctionItem)
    case custom(OpenResponsesCustomItem)
    case other(JSONObject)

    init(_ fields: JSONObject) throws {
        func parts(_ key: String) throws -> [OpenResponsesTextPart]? {
            guard let value = fields[key], value != .null else { return nil }
            guard case .array(let rows) = value else { throw InvalidResponseDataError(data: value, message: "Expected \(key) content array") }
            return try rows.map { value in
                guard case .object(let part) = value else { throw InvalidResponseDataError(data: value, message: "Expected content object") }
                return OpenResponsesTextPart(part)
            }
        }
        let id = openResponsesString(fields["id"])
        switch openResponsesString(fields["type"]) {
        case "reasoning": self = .reasoning(.init(id: id, content: try parts("content"), summary: try parts("summary"), encryptedContent: openResponsesString(fields["encrypted_content"])))
        case "message": self = .message(.init(id: id, content: try parts("content")))
        case "function_call": self = .function(.init(id: id, callId: openResponsesString(fields["call_id"]), name: openResponsesString(fields["name"]), arguments: openResponsesString(fields["arguments"])))
        case "custom_tool_call": self = .custom(.init(id: id, callId: openResponsesString(fields["call_id"]), name: openResponsesString(fields["name"]), input: openResponsesString(fields["input"])))
        default: self = .other(fields)
        }
    }
}

struct OpenResponsesResponse: Sendable {
    let id: String?
    let createdAt: Double?
    let model: String?
    let status: String?
    let incompleteReason: String?
    let error: OpenResponsesResponseError?
    let output: [OpenResponsesOutputItem]?
    let usage: OpenResponsesUsage?

    init(_ fields: JSONObject) throws {
        id = openResponsesString(fields["id"])
        createdAt = openResponsesNumber(fields["created_at"])
        model = openResponsesString(fields["model"])
        status = openResponsesString(fields["status"])
        if case .object(let incomplete) = fields["incomplete_details"] { incompleteReason = openResponsesString(incomplete["reason"]) }
        else { incompleteReason = nil }
        if let value = fields["error"], openResponsesTruthy(value) { error = try OpenResponsesResponseError(wire: value) }
        else { error = nil }
        if let value = fields["output"], value != .null {
            guard case .array(let items) = value else { throw InvalidResponseDataError(data: value, message: "Expected output array") }
            output = try items.map { value in
                guard case .object(let fields) = value else { throw InvalidResponseDataError(data: value, message: "Expected output item object") }
                return try OpenResponsesOutputItem(fields)
            }
        } else { output = nil }
        if let value = fields["usage"], value != .null { usage = try OpenResponsesUsage(value) }
        else { usage = nil }
    }
}

extension OpenResponsesResponseError {
    init(wire: JSONValue) throws {
        guard case .object(let fields) = wire, case .string(let message) = fields["message"] else {
            throw InvalidResponseDataError(data: wire, message: "Expected a response error message")
        }
        self.init(message: message, code: openResponsesString(fields["code"]), fields: fields)
    }
}

func openResponsesTruthy(_ value: JSONValue?) -> Bool {
    guard let value else { return false }
    switch value {
    case .null: return false
    case .bool(let value): return value
    case .number(let value): return value != 0 && !value.isNaN
    case .string(let value): return !value.isEmpty
    case .array, .object: return true
    }
}
func openResponsesString(_ value: JSONValue?) -> String? { if case .string(let value) = value { return value }; return nil }
func openResponsesNumber(_ value: JSONValue?) -> Double? { if case .number(let value) = value { return value }; return nil }
func openResponsesObject(_ value: JSONValue?) -> JSONObject? { if case .object(let value) = value { return value }; return nil }
func openResponsesJSONString<Value: Encodable>(_ value: Value) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    return String(decoding: try encoder.encode(value), as: UTF8.self)
}

func openResponsesReasoningMetadata(_ item: OpenResponsesReasoningItem, namespace: String, content: [OpenResponsesTextPart]? = nil, useExplicitContent: Bool = false) throws -> SharedV4ProviderMetadata {
    guard let summary = item.summary else { throw InvalidResponseDataError(data: item.id, message: "Expected reasoning summary array") }
    let content = useExplicitContent ? content : item.content
    func textParts(_ parts: [OpenResponsesTextPart], type: String) throws -> JSONValue {
        .array(try parts.map { part in
            guard let text = part.text else { throw InvalidResponseDataError(data: item.id, message: "Expected reasoning text") }
            return .object(["type": .string(type), "text": .string(text)])
        })
    }
    var data: JSONObject = ["reasoningSummary": try textParts(summary, type: "summary_text"), "reasoningContent": .null]
    if let id = item.id { data["itemId"] = .string(id) }
    if let content { data["reasoningContent"] = try textParts(content, type: "reasoning_text") }
    if let encrypted = item.encryptedContent { data["reasoningEncryptedContent"] = .string(encrypted) }
    return [namespace: data]
}

let openResponsesJSONSchema = FlexibleSchema(jsonSchema(.bool(true)))

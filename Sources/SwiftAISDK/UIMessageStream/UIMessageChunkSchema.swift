import Foundation
import AISDKProvider
import AISDKProviderUtils

public let uiMessageChunkSchema = FlexibleSchema<AnyUIMessageChunk>(Schema(
    jsonSchemaResolver: { uiChunkJSONSchema },
    validator: { value in
        let json = try jsonValue(from: value)
        switch await uiChunkValueSchema.validate(json) {
        case .failure(let error): return .failure(error: error)
        case .success: return .success(value: try parseUIMessageChunk(json))
        }
    }
))

private let chunkFields: [(String, [String], [String])] = [
    ("text-start", ["id"], ["providerMetadata"]),
    ("text-delta", ["id", "delta"], ["providerMetadata"]),
    ("text-end", ["id"], ["providerMetadata", "citations"]),
    ("reasoning-start", ["id"], ["providerMetadata"]),
    ("reasoning-delta", ["id", "delta"], ["providerMetadata"]),
    ("reasoning-end", ["id"], ["providerMetadata"]),
    ("custom", ["kind"], ["providerMetadata"]),
    ("error", ["errorText"], []),
    ("tool-input-start", ["toolCallId", "toolName"], ["inputEncoding", "providerExecuted", "providerMetadata", "toolMetadata", "dynamic", "title"]),
    ("tool-input-delta", ["toolCallId", "inputTextDelta"], []),
    ("tool-input-available", ["toolCallId", "toolName", "input"], ["providerExecuted", "providerMetadata", "toolMetadata", "dynamic", "title"]),
    ("tool-input-error", ["toolCallId", "toolName", "input", "errorText"], ["providerExecuted", "providerMetadata", "toolMetadata", "dynamic", "title"]),
    ("tool-approval-request", ["approvalId", "toolCallId"], ["approvalDescriptor", "inputSchemaInput", "reason", "isAutomatic", "signature"]),
    ("tool-approval-response", ["approvalId", "approved"], ["reason", "providerExecuted", "providerMetadata"]),
    ("tool-output-available", ["toolCallId", "output"], ["providerExecuted", "providerMetadata", "toolMetadata", "dynamic", "preliminary"]),
    ("tool-output-error", ["toolCallId", "errorText"], ["providerExecuted", "providerMetadata", "toolMetadata", "dynamic"]),
    ("tool-output-denied", ["toolCallId"], []),
    ("source-url", ["sourceId", "url"], ["title", "providerMetadata"]),
    ("source-document", ["sourceId", "mediaType", "title"], ["filename", "providerMetadata"]),
    ("file", ["url", "mediaType"], ["providerMetadata"]),
    ("reasoning-file", ["url", "mediaType"], ["providerMetadata"]),
    ("start-step", [], []), ("finish-step", [], []), ("reset-step", [], []),
    ("start", [], ["messageId", "messageMetadata"]),
    ("finish", [], ["finishReason", "messageMetadata"]),
    ("abort", [], ["reason"]), ("message-metadata", ["messageMetadata"], [])
]

private let uiChunkJSONSchema = chunkJSONSchema()
private let uiChunkValueSchema = jsonSchema(uiChunkJSONSchema)

private func chunkJSONSchema() -> JSONValue {
    func field(_ key: String) -> JSONValue {
        switch key {
        case "input", "output", "data", "messageMetadata", "approvalDescriptor", "inputSchemaInput": return .object([:])
        case "providerExecuted", "dynamic", "preliminary", "transient", "approved", "isAutomatic":
            return .object(["type": .string("boolean")])
        case "providerMetadata":
            return .object(["type": .string("object"), "additionalProperties": .object(["type": .string("object")])])
        case "toolMetadata": return .object(["type": .string("object")])
        case "citations": return .object(["type": .string("array"), "items": uiCitationJSONSchema()])
        case "inputEncoding": return .object(["enum": .array([.string("json"), .string("text")])])
        case "finishReason": return .object(["enum": .array(["stop", "length", "content-filter", "tool-calls", "error", "other"].map(JSONValue.string))])
        default: return .object(["type": .string("string")])
        }
    }
    var variants = chunkFields.map { type, required, optional -> JSONValue in
        var properties = Dictionary(uniqueKeysWithValues: (required + optional).map { ($0, field($0)) })
        properties["type"] = .object(["const": .string(type)])
        return .object(["type": .string("object"), "properties": .object(properties),
                        "required": .array((["type"] + required).map(JSONValue.string))])
    }
    variants.append(.object([
        "type": .string("object"),
        "properties": .object(["type": .object(["type": .string("string"), "pattern": .string("^data-")]),
                               "id": field("id"), "data": field("data"), "transient": field("transient")]),
        "required": .array([.string("type"), .string("data")])
    ]))
    return .object(["anyOf": .array(variants)])
}

private func parseUIMessageChunk(_ json: JSONValue) throws -> AnyUIMessageChunk {
    guard case .object(let object) = json else { throw ChunkShapeError() }
    func string(_ key: String) throws -> String {
        guard case .string(let value) = object[key] else { throw ChunkShapeError() }
        return value
    }
    func optionalString(_ key: String) -> String? { if case .string(let value) = object[key] { return value }; return nil }
    func bool(_ key: String) -> Bool? { if case .bool(let value) = object[key] { return value }; return nil }
    func dictionary(_ key: String) -> JSONObject? { if case .object(let value) = object[key] { return value }; return nil }
    let metadata = dictionary("providerMetadata")?.compactMapValues { value -> JSONObject? in
        if case .object(let result) = value { return result }; return nil
    }
    let toolMetadata = dictionary("toolMetadata")
    let type = try string("type")
    switch type {
    case "text-start": return .textStart(id: try string("id"), providerMetadata: metadata)
    case "text-delta": return .textDelta(id: try string("id"), delta: try string("delta"), providerMetadata: metadata)
    case "text-end":
        let citations = try object["citations"].map(parseUICitations)
        return .textEnd(id: try string("id"), providerMetadata: metadata, citations: citations)
    case "reasoning-start": return .reasoningStart(id: try string("id"), providerMetadata: metadata)
    case "reasoning-delta": return .reasoningDelta(id: try string("id"), delta: try string("delta"), providerMetadata: metadata)
    case "reasoning-end": return .reasoningEnd(id: try string("id"), providerMetadata: metadata)
    case "custom": return .custom(kind: try string("kind"), providerMetadata: metadata)
    case "file": return .file(url: try string("url"), mediaType: try string("mediaType"), providerMetadata: metadata)
    case "reasoning-file": return .reasoningFile(url: try string("url"), mediaType: try string("mediaType"), providerMetadata: metadata)
    case "source-url": return .sourceUrl(sourceId: try string("sourceId"), url: try string("url"), title: optionalString("title"), providerMetadata: metadata)
    case "source-document": return .sourceDocument(sourceId: try string("sourceId"), mediaType: try string("mediaType"), title: try string("title"), filename: optionalString("filename"), providerMetadata: metadata)
    case "tool-input-start":
        return .toolInputStart(toolCallId: try string("toolCallId"), toolName: try string("toolName"), providerExecuted: bool("providerExecuted"), providerMetadata: metadata, dynamic: bool("dynamic"), title: optionalString("title"), toolMetadata: toolMetadata, inputEncoding: optionalString("inputEncoding").flatMap(UIToolInputEncoding.init(rawValue:)))
    case "tool-input-delta": return .toolInputDelta(toolCallId: try string("toolCallId"), inputTextDelta: try string("inputTextDelta"))
    case "tool-input-available":
        return .toolInputAvailable(toolCallId: try string("toolCallId"), toolName: try string("toolName"), input: object["input"] ?? .null, providerExecuted: bool("providerExecuted"), providerMetadata: metadata, dynamic: bool("dynamic"), title: optionalString("title"), toolMetadata: toolMetadata)
    case "tool-input-error":
        return .toolInputError(toolCallId: try string("toolCallId"), toolName: try string("toolName"), input: object["input"] ?? .null, providerExecuted: bool("providerExecuted"), providerMetadata: metadata, dynamic: bool("dynamic"), errorText: try string("errorText"), title: optionalString("title"), toolMetadata: toolMetadata)
    case "tool-output-available":
        return .toolOutputAvailable(toolCallId: try string("toolCallId"), output: object["output"] ?? .null, providerExecuted: bool("providerExecuted"), providerMetadata: metadata, dynamic: bool("dynamic"), preliminary: bool("preliminary"), toolMetadata: toolMetadata)
    case "tool-output-error":
        return .toolOutputError(toolCallId: try string("toolCallId"), errorText: try string("errorText"), providerExecuted: bool("providerExecuted"), providerMetadata: metadata, dynamic: bool("dynamic"), toolMetadata: toolMetadata)
    case "tool-output-denied": return .toolOutputDenied(toolCallId: try string("toolCallId"))
    case "tool-approval-request": return .toolApprovalRequest(approvalId: try string("approvalId"), toolCallId: try string("toolCallId"), approvalDescriptor: object["approvalDescriptor"], inputSchemaInput: object["inputSchemaInput"], reason: optionalString("reason"), isAutomatic: bool("isAutomatic"), signature: optionalString("signature"))
    case "tool-approval-response":
        guard let approved = bool("approved") else { throw ChunkShapeError() }
        return .toolApprovalResponse(approvalId: try string("approvalId"), approved: approved, reason: optionalString("reason"), providerExecuted: bool("providerExecuted"), providerMetadata: metadata)
    case "start-step": return .startStep
    case "finish-step": return .finishStep
    case "reset-step": return .resetStep
    case "start": return .start(messageId: optionalString("messageId"), messageMetadata: object["messageMetadata"])
    case "finish": return .finish(finishReason: optionalString("finishReason").flatMap(FinishReason.init(rawValue:)), messageMetadata: object["messageMetadata"])
    case "abort": return .abort(reason: optionalString("reason"))
    case "error": return .error(errorText: try string("errorText"))
    case "message-metadata": return .messageMetadata(object["messageMetadata"] ?? .null)
    default:
        guard type.hasPrefix("data-") else { throw ChunkShapeError() }
        return .data(DataUIMessageChunk(name: String(type.dropFirst(5)), id: optionalString("id"), data: object["data"] ?? .null, transient: bool("transient")))
    }
}

private struct ChunkShapeError: LocalizedError {
    var errorDescription: String? { "Invalid UI message chunk" }
}

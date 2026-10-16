import AISDKProvider
import AISDKProviderUtils

// Metadata retains explicit nulls while stripping unknown keys like upstream.
indirect enum GoogleWireSchema: Sendable {
    case string, number, tokenCount, boolean, any
    case array(GoogleWireSchema)
    case object(required: [String: GoogleWireSchema] = [:], optional: [String: GoogleWireSchema] = [:], loose: Bool = false)
    case union([GoogleWireSchema])

    func parse(_ value: JSONValue) throws -> JSONValue {
        switch (self, value) {
        case (.any, _), (.string, .string), (.number, .number), (.boolean, .bool): return value
        case (.tokenCount, .number(let count)) where Int(exactly: count) != nil: return value
        case (.array(let item), .array(let values)): return .array(try values.map(item.parse))
        case (.object(let required, let optional, let loose), .object(let object)):
            var result: JSONObject = loose ? object : [:]
            for (key, schema) in required {
                guard let field = object[key] else { throw SchemaValidationIssuesError(vendor: "google", issues: "missing response field \(key)") }
                result[key] = try schema.parse(field)
            }
            for (key, schema) in optional {
                if let field = object[key] { result[key] = field == .null ? .null : try schema.parse(field) }
            }
            return .object(result)
        case (.union(let schemas), _):
            for schema in schemas { if let parsed = try? schema.parse(value) { return parsed } }
            fallthrough
        default: throw SchemaValidationIssuesError(vendor: "google", issues: "invalid response field")
        }
    }
    var jsonSchema: JSONValue {
        switch self {
        case .any: return .object([:])
        case .string: return .object(["type": .string("string")])
        case .number: return .object(["type": .string("number")])
        case .tokenCount: return .object(["type": .string("integer")])
        case .boolean: return .object(["type": .string("boolean")])
        case .array(let item): return .object(["type": .string("array"), "items": item.jsonSchema])
        case .union(let schemas): return .object(["anyOf": .array(schemas.map(\.jsonSchema))])
        case .object(let required, let optional, let loose):
            var fields = required.mapValues(\.jsonSchema)
            for (key, value) in optional { fields[key] = .object(["anyOf": .array([value.jsonSchema, .object(["type": .string("null")])])]) }
            return .object(["type": .string("object"), "properties": .object(fields), "required": .array(required.keys.sorted().map(JSONValue.string)), "additionalProperties": .bool(loose)])
        }
    }
    var schema: Schema<JSONValue> {
        Schema(jsonSchemaResolver: { self.jsonSchema }, validator: { value in
            do { return .success(value: try self.parse(jsonValue(from: value))) }
            catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
        })
    }
}

let googleSafetyWire = GoogleWireSchema.object(optional: ["category": .string, "probability": .string, "probabilityScore": .number, "severity": .string, "severityScore": .number, "blocked": .boolean])
let googleGroundingWire = GoogleWireSchema.object(optional: [
    "webSearchQueries": .array(.string), "imageSearchQueries": .array(.string), "retrievalQueries": .array(.string),
    "searchEntryPoint": .object(required: ["renderedContent": .string]),
    "groundingChunks": .array(.object(optional: [
        "web": .object(required: ["uri": .string], optional: ["title": .string]),
        "image": .object(required: ["sourceUri": .string, "imageUri": .string], optional: ["title": .string, "domain": .string]),
        "retrievedContext": .object(optional: [
            "uri": .string, "title": .string, "text": .string, "fileSearchStore": .string,
            "customMetadata": .array(.object(required: ["key": .string], optional: ["stringValue": .string, "numericValue": .number, "stringListValue": .object(optional: ["values": .array(.string)])]))
        ]),
        "maps": .object(optional: ["uri": .string, "title": .string, "text": .string, "placeId": .string])
    ])),
    "groundingSupports": .array(.object(optional: [
        "segment": .object(optional: ["startIndex": .number, "endIndex": .number, "text": .string]),
        "segment_text": .string, "groundingChunkIndices": .array(.number), "supportChunkIndices": .array(.number), "confidenceScores": .array(.number), "confidenceScore": .array(.number)
    ])),
    "retrievalMetadata": .union([.object(required: ["webDynamicRetrievalScore": .number]), .object()])
])
let googleUrlContextWire = GoogleWireSchema.object(optional: ["urlMetadata": .array(.object(required: ["retrievedUrl": .string, "urlRetrievalStatus": .string]))])
private let googleTokenDetailsWire = GoogleWireSchema.array(.object(required: ["modality": .string, "tokenCount": .number], loose: true))
private let googleUsageWire = GoogleWireSchema.object(optional: [
    "cachedContentTokenCount": .tokenCount, "thoughtsTokenCount": .tokenCount, "promptTokenCount": .tokenCount, "candidatesTokenCount": .tokenCount, "toolUsePromptTokenCount": .tokenCount, "totalTokenCount": .tokenCount,
    "trafficType": .string, "serviceTier": .string, "promptTokensDetails": googleTokenDetailsWire, "cacheTokensDetails": googleTokenDetailsWire, "candidatesTokensDetails": googleTokenDetailsWire, "toolUsePromptTokensDetails": googleTokenDetailsWire
], loose: true)
private let googlePartWire = GoogleWireSchema.union([
    .object(required: ["functionCall": .object(optional: ["id": .string, "name": .string, "args": .any, "partialArgs": .array(.object(required: ["jsonPath": .string], optional: ["stringValue": .string, "numberValue": .number, "boolValue": .boolean, "nullValue": .any, "willContinue": .boolean])), "willContinue": .boolean])], optional: ["thoughtSignature": .string]),
    .object(required: ["inlineData": .object(required: ["mimeType": .string, "data": .string])], optional: ["thought": .boolean, "thoughtSignature": .string]),
    .object(required: ["toolCall": .object(required: ["toolType": .string, "id": .string], optional: ["args": .any])], optional: ["thoughtSignature": .string]),
    .object(required: ["toolResponse": .object(required: ["toolType": .string, "id": .string], optional: ["response": .any])], optional: ["thoughtSignature": .string]),
    .object(optional: ["executableCode": .object(required: ["language": .string, "code": .string]), "codeExecutionResult": .object(required: ["outcome": .string], optional: ["output": .string]), "text": .string, "thought": .boolean, "thoughtSignature": .string])
])
let googleResponseWire = GoogleWireSchema.object(optional: [
    "responseId": .string,
    "candidates": .array(.object(optional: [
        "content": .object(optional: ["parts": .array(googlePartWire)]), "finishReason": .string, "finishMessage": .string, "continuationToken": .string,
        "safetyRatings": .array(googleSafetyWire), "groundingMetadata": googleGroundingWire, "urlContextMetadata": googleUrlContextWire
    ])),
    "usageMetadata": googleUsageWire,
    "promptFeedback": .object(optional: ["blockReason": .string, "safetyRatings": .array(googleSafetyWire)])
])

import Foundation
import AISDKProvider
import AISDKProviderUtils

struct PerplexityObject {
    struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(_ value: String) { stringValue = value }
        init?(stringValue: String) { self.init(stringValue) }
        init?(intValue: Int) { return nil }
    }
    let fields: JSONObject
    private let container: KeyedDecodingContainer<Key>

    init(_ decoder: Decoder) throws {
        fields = try decoder.singleValueContainer().decode(JSONObject.self)
        container = try decoder.container(keyedBy: Key.self)
    }
    func required<Value: Decodable>(_ type: Value.Type, _ key: String) throws -> Value {
        try container.decode(type, forKey: Key(key))
    }
    func optional<Value: Decodable>(_ type: Value.Type, _ key: String, nullable: Bool = false) throws -> Value? {
        let key = Key(key)
        if nullable { return try container.decodeIfPresent(type, forKey: key) }
        guard container.contains(key) else { return Optional<Value>.none }
        return try container.decode(type, forKey: key)
    }
}

struct PerplexitySearchResult: Decodable, Sendable {
    let id: Double?
    let title: String
    let url: String
    let snippet: String?
    let date: String?
    let lastUpdated: String?
    let source: String?
    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        id = try value.optional(Double.self, "id")
        title = try value.required(String.self, "title")
        url = try value.required(String.self, "url")
        snippet = try value.optional(String.self, "snippet")
        date = try value.optional(String.self, "date", nullable: true)
        lastUpdated = try value.optional(String.self, "last_updated", nullable: true)
        source = try value.optional(String.self, "source")
    }
}

struct PerplexityFetchedContent: Decodable, Sendable {
    let title: String
    let url: String
    let snippet: String?
    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        title = try value.required(String.self, "title")
        url = try value.required(String.self, "url")
        snippet = try value.optional(String.self, "snippet")
    }
}

struct PerplexityContentPart: Decodable, Sendable {
    struct Annotation: Decodable, Sendable {
        let type: String?
        let url: String?
        let title: String?
        init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            type = try value.optional(String.self, "type")
            url = try value.optional(String.self, "url")
            title = try value.optional(String.self, "title")
        }
    }
    let type: String
    let text: String?
    let annotations: [Annotation]?
    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        type = try value.required(String.self, "type")
        text = try value.optional(String.self, "text")
        annotations = try value.optional([Annotation].self, "annotations", nullable: true)
    }
}

enum PerplexityOutputItem: Decodable, Sendable {
    case message(id: String?, content: [PerplexityContentPart]?)
    case searchResults([PerplexitySearchResult]?)
    case fetchedContents([PerplexityFetchedContent]?)
    case functionCall(FunctionCall)
    case unhandled

    struct FunctionCall: Sendable {
        let id: String?
        let callId: String?
        let name: String?
        let arguments: String?
        let thoughtSignature: String?
    }

    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        switch try value.required(String.self, "type") {
        case "message":
            self = .message(id: try value.optional(String.self, "id", nullable: true), content: try value.optional([PerplexityContentPart].self, "content", nullable: true))
        case "search_results": self = .searchResults(try value.optional([PerplexitySearchResult].self, "results", nullable: true))
        case "fetch_url_results": self = .fetchedContents(try value.optional([PerplexityFetchedContent].self, "contents", nullable: true))
        case "function_call":
            self = .functionCall(.init(
                id: try value.optional(String.self, "id", nullable: true), callId: try value.optional(String.self, "call_id", nullable: true),
                name: try value.optional(String.self, "name", nullable: true), arguments: try value.optional(String.self, "arguments", nullable: true),
                thoughtSignature: try value.optional(String.self, "thought_signature", nullable: true)
            ))
        default: self = .unhandled
        }
    }
}

struct PerplexityAgentResponse: Decodable, Sendable {
    struct Incomplete: Decodable, Sendable { let reason: String }
    struct Failure: Decodable, Sendable {
        let message: String
        let code: String?
        let type: String?
        init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            message = try value.required(String.self, "message")
            code = try value.optional(String.self, "code")
            type = try value.optional(String.self, "type")
        }
    }
    let id: String
    let createdAt: Double
    let model: String
    let output: [PerplexityOutputItem]
    let status: String
    let incomplete: Incomplete?
    let error: Failure?
    let usage: PerplexityUsage?

    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        let object = try value.required(String.self, "object")
        guard object == "response" else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Expected Agent response object"))
        }
        id = try value.required(String.self, "id")
        createdAt = try value.required(Double.self, "created_at")
        model = try value.required(String.self, "model")
        output = try value.required([PerplexityOutputItem].self, "output")
        status = try value.required(String.self, "status")
        incomplete = try value.optional(Incomplete.self, "incomplete_details", nullable: true)
        error = try value.optional(Failure.self, "error", nullable: true)
        usage = try value.optional(PerplexityUsage.self, "usage", nullable: true)
    }
}

struct PerplexityAgentChunk: Decodable, Sendable {
    struct Failure: Decodable, Sendable {
        let raw: JSONObject
        init(from decoder: Decoder) throws {
            let value = try PerplexityObject(decoder)
            _ = try value.required(String.self, "message")
            _ = try value.optional(String.self, "code", nullable: true)
            _ = try value.optional(String.self, "type", nullable: true)
            raw = value.fields
        }
    }
    let type: String
    let sequenceNumber: Double?
    let response: PerplexityAgentResponse?
    let item: PerplexityOutputItem?
    let outputIndex: Double?
    let itemId: String?
    let contentIndex: Double?
    let delta: String?
    let text: String?
    let thought: String?
    let results: [PerplexitySearchResult]?
    let contents: [PerplexityFetchedContent]?
    let error: Failure?

    init(from decoder: Decoder) throws {
        let value = try PerplexityObject(decoder)
        type = try value.required(String.self, "type")
        sequenceNumber = try value.optional(Double.self, "sequence_number", nullable: true)
        response = try value.optional(PerplexityAgentResponse.self, "response", nullable: true)
        item = try value.optional(PerplexityOutputItem.self, "item", nullable: true)
        outputIndex = try value.optional(Double.self, "output_index", nullable: true)
        itemId = try value.optional(String.self, "item_id", nullable: true)
        contentIndex = try value.optional(Double.self, "content_index", nullable: true)
        delta = try value.optional(String.self, "delta", nullable: true)
        text = try value.optional(String.self, "text", nullable: true)
        thought = try value.optional(String.self, "thought", nullable: true)
        _ = try value.optional([String].self, "queries", nullable: true)
        _ = try value.optional([String].self, "urls", nullable: true)
        results = try value.optional([PerplexitySearchResult].self, "results", nullable: true)
        contents = try value.optional([PerplexityFetchedContent].self, "contents", nullable: true)
        error = try value.optional(Failure.self, "error", nullable: true)
    }
}

let perplexityAgentResponseSchema = FlexibleSchema(Schema<PerplexityAgentResponse>.codable(PerplexityAgentResponse.self, jsonSchema: ["type": "object"]))
let perplexityAgentChunkSchema = FlexibleSchema(Schema<PerplexityAgentChunk>.codable(PerplexityAgentChunk.self, jsonSchema: ["type": "object"]))

import Foundation
import AISDKProvider

func parseUICitations(_ value: JSONValue) throws -> [Citation] {
    guard case .array(let entries) = value else { throw InvalidUICitation() }
    for entry in entries {
        guard case .object(let citation) = entry,
              case .object(let source) = citation["source"],
              source["type"] == .string("source"),
              case .string(let sourceType) = source["sourceType"] else { throw InvalidUICitation() }
        let required: [String]
        let optional: [String]
        switch sourceType {
        case "url": required = ["id", "url"]; optional = ["title"]
        case "document": required = ["id", "mediaType", "title"]; optional = ["filename"]
        default: throw InvalidUICitation()
        }
        for key in required {
            guard case .string = source[key] else { throw InvalidUICitation() }
        }
        for key in optional where source[key] != nil {
            guard case .string = source[key] else { throw InvalidUICitation() }
        }
        if let metadata = source["providerMetadata"] {
            guard case .object(let providers) = metadata else { throw InvalidUICitation() }
            for value in providers.values {
                guard case .object = value else { throw InvalidUICitation() }
            }
        }
        for key in ["startIndex", "endIndex"] where citation[key] != nil {
            guard case .number(let number) = citation[key], number.isFinite,
                  number >= 0, number.rounded(.towardZero) == number else { throw InvalidUICitation() }
        }
        if let text = citation["citedText"] {
            guard case .string = text else { throw InvalidUICitation() }
        }
    }
    return try JSONDecoder().decode([Citation].self, from: JSONEncoder().encode(value))
}

func uiCitationJSONSchema() -> JSONValue {
    let string: JSONValue = .object(["type": .string("string")])
    let metadata: JSONValue = .object([
        "type": .string("object"), "additionalProperties": .object(["type": .string("object")])
    ])
    func source(_ type: String, required: [String], optional: [String]) -> JSONValue {
        var properties = Dictionary(uniqueKeysWithValues: (required + optional).map { ($0, string) })
        properties["type"] = .object(["const": .string("source")])
        properties["sourceType"] = .object(["const": .string(type)])
        properties["providerMetadata"] = metadata
        return .object([
            "type": .string("object"), "properties": .object(properties),
            "required": .array((["type", "sourceType"] + required).map(JSONValue.string))
        ])
    }
    return .object([
        "type": .string("object"), "required": .array([.string("source")]),
        "properties": .object([
            "source": .object(["anyOf": .array([
                source("url", required: ["id", "url"], optional: ["title"]),
                source("document", required: ["id", "mediaType", "title"], optional: ["filename"])
            ])]),
            "startIndex": .object(["type": .string("integer"), "minimum": .number(0)]),
            "endIndex": .object(["type": .string("integer"), "minimum": .number(0)]),
            "citedText": string
        ])
    ])
}

private struct InvalidUICitation: LocalizedError {
    var errorDescription: String? { "Invalid citation" }
}

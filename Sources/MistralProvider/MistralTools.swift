import Foundation
import AISDKProvider
import AISDKProviderUtils

private struct SearchInput: Codable, Sendable {
    let arguments: String
}

private struct SearchOutput: Codable, Sendable {
    let info: JSONObject?

    private enum CodingKeys: String, CodingKey { case info }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        info = container.contains(.info) ? try container.decode(JSONObject.self, forKey: .info) : nil
    }
}

private func searchSchema<Value: Codable & Sendable>(_ type: Value.Type, jsonSchema: JSONValue) -> FlexibleSchema<JSONValue> {
    FlexibleSchema(Schema<JSONValue>(jsonSchemaResolver: { jsonSchema }, validator: { raw in
        do {
            let value = try JSONDecoder().decode(type, from: JSONEncoder().encode(jsonValue(from: raw)))
            let output = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
            return .success(value: output)
        } catch {
            return .failure(error: TypeValidationError.wrap(value: raw, cause: error))
        }
    }))
}

private let searchInputSchema = searchSchema(SearchInput.self, jsonSchema: [
    "type": "object", "properties": ["arguments": ["type": "string"]],
    "required": ["arguments"], "additionalProperties": false
])
private let searchOutputSchema = searchSchema(SearchOutput.self, jsonSchema: [
    "type": "object", "properties": ["info": ["type": "object", "additionalProperties": true]], "additionalProperties": false
])
private let webSearchFactory = createProviderExecutedToolFactory(
    id: "mistral.web_search", name: "web_search", inputSchema: searchInputSchema, outputSchema: searchOutputSchema
)
private let webSearchPremiumFactory = createProviderExecutedToolFactory(
    id: "mistral.web_search_premium", name: "web_search_premium", inputSchema: searchInputSchema, outputSchema: searchOutputSchema
)

public struct MistralTools: Sendable {
    public init() {}

    public func webSearch(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        webSearchFactory(options)
    }

    public func webSearchPremium(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool {
        webSearchPremiumFactory(options)
    }
}

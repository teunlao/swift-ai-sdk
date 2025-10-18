import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesRequestBody: Encodable, Sendable {
    var model: String
    var input: OpenAIResponsesInput
    var temperature: Double?
    var topP: Double?
    var maxOutputTokens: Int?
    var text: JSONValue?
    var maxToolCalls: Int?
    var metadata: JSONValue?
    var parallelToolCalls: Bool?
    var previousResponseId: String?
    var store: Bool?
    var user: String?
    var instructions: String?
    var serviceTier: String?
    var include: [String]?
    var promptCacheKey: String?
    var safetyIdentifier: String?
    var topLogprobs: Int?
    var reasoning: JSONValue?
    var truncation: String?
    var tools: [JSONValue]?
    var toolChoice: JSONValue?
    var stream: Bool?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case temperature
        case topP = "top_p"
        case maxOutputTokens = "max_output_tokens"
        case text
        case maxToolCalls = "max_tool_calls"
        case metadata
        case parallelToolCalls = "parallel_tool_calls"
        case previousResponseId = "previous_response_id"
        case store
        case user
        case instructions
        case serviceTier = "service_tier"
        case include
        case promptCacheKey = "prompt_cache_key"
        case safetyIdentifier = "safety_identifier"
        case topLogprobs = "top_logprobs"
        case reasoning
        case truncation
        case tools
        case toolChoice = "tool_choice"
        case stream
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(topP, forKey: .topP)
        try container.encodeIfPresent(maxOutputTokens, forKey: .maxOutputTokens)
        try container.encodeIfPresent(text, forKey: .text)
        try container.encodeIfPresent(maxToolCalls, forKey: .maxToolCalls)
        try container.encodeIfPresent(metadata, forKey: .metadata)
        try container.encodeIfPresent(parallelToolCalls, forKey: .parallelToolCalls)
        try container.encodeIfPresent(previousResponseId, forKey: .previousResponseId)
        try container.encodeIfPresent(store, forKey: .store)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(instructions, forKey: .instructions)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(include, forKey: .include)
        try container.encodeIfPresent(promptCacheKey, forKey: .promptCacheKey)
        try container.encodeIfPresent(safetyIdentifier, forKey: .safetyIdentifier)
        try container.encodeIfPresent(topLogprobs, forKey: .topLogprobs)
        try container.encodeIfPresent(reasoning, forKey: .reasoning)
        try container.encodeIfPresent(truncation, forKey: .truncation)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        try container.encodeIfPresent(stream, forKey: .stream)
    }
}

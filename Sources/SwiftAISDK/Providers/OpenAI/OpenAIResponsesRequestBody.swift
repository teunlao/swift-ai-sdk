import Foundation
import AISDKProviderUtils
import AISDKProvider

struct OpenAIResponsesRequestBody: Encodable, Sendable {
    let model: String
    let input: [JSONValue]
    let temperature: Double?
    let topP: Double?
    let maxOutputTokens: Int?
    let text: JSONValue?
    let maxToolCalls: Int?
    let metadata: JSONValue?
    let parallelToolCalls: Bool?
    let previousResponseId: String?
    let store: Bool?
    let user: String?
    let instructions: String?
    let serviceTier: String?
    let include: [String]?
    let promptCacheKey: String?
    let safetyIdentifier: String?
    let topLogprobs: Int?
    let reasoning: JSONValue?
    let tools: [JSONValue]?
    let toolChoice: JSONValue?

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
        case tools
        case toolChoice = "tool_choice"
    }
}

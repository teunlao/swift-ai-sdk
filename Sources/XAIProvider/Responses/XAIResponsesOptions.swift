import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum XAIResponsesReasoningEffort: String, Sendable, Equatable, Codable {
    case none, low, medium, high, xhigh
}

public struct XAILanguageModelResponsesOptions: Sendable, Equatable, Codable {
    public var reasoningEffort: XAIResponsesReasoningEffort?
    public var logprobs: Bool?
    public var topLogprobs: Int?
    public var minP: Double?
    public var maxTurns: Int?
    public var parallelToolCalls: Bool?
    public var promptCacheKey: String?
    public var safetyIdentifier: String?
    public var serviceTier: String?
    public var store: Bool?
    public var previousResponseId: String?
    public var user: String?
    public var include: [String]?

    public init(
        reasoningEffort: XAIResponsesReasoningEffort? = nil, logprobs: Bool? = nil, topLogprobs: Int? = nil,
        minP: Double? = nil, maxTurns: Int? = nil, parallelToolCalls: Bool? = nil, promptCacheKey: String? = nil,
        safetyIdentifier: String? = nil, serviceTier: String? = nil, store: Bool? = nil,
        previousResponseId: String? = nil, user: String? = nil, include: [String]? = nil
    ) {
        self.reasoningEffort = reasoningEffort
        self.logprobs = logprobs
        self.topLogprobs = topLogprobs
        self.minP = minP
        self.maxTurns = maxTurns
        self.parallelToolCalls = parallelToolCalls
        self.promptCacheKey = promptCacheKey
        self.safetyIdentifier = safetyIdentifier
        self.serviceTier = serviceTier
        self.store = store
        self.previousResponseId = previousResponseId
        self.user = user
        self.include = include
    }
}

public let xaiLanguageModelResponsesOptionsSchema = FlexibleSchema(
    Schema<XAILanguageModelResponsesOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
        do {
            let json = try jsonValue(from: value)
            guard case .object(let object) = json else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected an object") }
            let fields = ["reasoningEffort", "logprobs", "topLogprobs", "minP", "maxTurns", "parallelToolCalls", "promptCacheKey", "safetyIdentifier", "serviceTier", "store", "previousResponseId", "user"]
            for field in fields where object[field] == .null {
                throw InvalidArgumentError(argument: field, message: "Expected a non-null option")
            }
            let options = try JSONDecoder().decode(XAILanguageModelResponsesOptions.self, from: JSONEncoder().encode(json))
            if let top = options.topLogprobs, !(0...8).contains(top) { throw InvalidArgumentError(argument: "topLogprobs", message: "Expected an integer between 0 and 8") }
            if let minP = options.minP, !(0...1).contains(minP) { throw InvalidArgumentError(argument: "minP", message: "Expected a number between 0 and 1") }
            if let tier = options.serviceTier, !["default", "priority"].contains(tier) { throw InvalidArgumentError(argument: "serviceTier", message: "Expected default or priority") }
            let includes = Set(["file_search_call.results", "web_search_call.action.sources", "code_interpreter_call.outputs", "reasoning.encrypted_content", "no_inline_citations"])
            if let include = options.include, !include.allSatisfy(includes.contains) { throw InvalidArgumentError(argument: "include", message: "Invalid include value") }
            return .success(value: options)
        } catch {
            return .failure(error: TypeValidationError.wrap(value: value, cause: error))
        }
    })
)

func supportsReasoningEffort(_ modelId: String) -> Bool {
    modelId.range(of: #"^grok-4\.20(-\d{4})?-(non-)?reasoning$"#, options: .regularExpression) == nil
}

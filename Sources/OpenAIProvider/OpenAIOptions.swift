import AISDKProvider

extension OpenAILanguageModelResponsesOptions: Encodable {
    public func encode(to encoder: Encoder) throws {
        try OpenAIOptions().responses(self)["openai"]!.encode(to: encoder)
    }
}

public struct OpenAIOptions: Sendable {
    public init() {}

    public func responses(
        _ options: OpenAILanguageModelResponsesOptions = .init(),
        extra: [String: JSONValue] = [:]
    ) -> SharedV4ProviderOptions {
        var value = extra
        for key in options.nullFields { value[key] = .null }
        if let field = options.conversation { value["conversation"] = .string(field) }
        if let field = options.include { value["include"] = .array(field.map { .string($0.rawValue) }) }
        if let field = options.includeWebSearchSources { value["includeWebSearchSources"] = .bool(field) }
        if let field = options.instructions { value["instructions"] = .string(field) }
        if let field = options.logprobs {
            switch field {
            case .bool(let flag): value["logprobs"] = .bool(flag)
            case .number(let number): value["logprobs"] = .number(number)
            }
        }
        if let field = options.maxToolCalls { value["maxToolCalls"] = .number(field) }
        if let field = options.metadata { value["metadata"] = field }
        if let field = options.parallelToolCalls { value["parallelToolCalls"] = .bool(field) }
        if let field = options.previousResponseId { value["previousResponseId"] = .string(field) }
        if let field = options.promptCacheKey { value["promptCacheKey"] = .string(field) }
        if let field = options.promptCacheOptions { value["promptCacheOptions"] = field.jsonValue }
        if let field = options.promptCacheRetention { value["promptCacheRetention"] = .string(field) }
        if let field = options.reasoningEffort { value["reasoningEffort"] = .string(field) }
        if let field = options.reasoningMode { value["reasoningMode"] = .string(field.rawValue) }
        if let field = options.reasoningContext { value["reasoningContext"] = .string(field.rawValue) }
        if let field = options.reasoningSummary { value["reasoningSummary"] = .string(field) }
        if let field = options.safetyIdentifier { value["safetyIdentifier"] = .string(field) }
        if let field = options.serviceTier { value["serviceTier"] = .string(field) }
        if let field = options.store { value["store"] = .bool(field) }
        if let field = options.passThroughUnsupportedFiles { value["passThroughUnsupportedFiles"] = .bool(field) }
        if let field = options.strictJsonSchema { value["strictJsonSchema"] = .bool(field) }
        if let field = options.textVerbosity { value["textVerbosity"] = .string(field) }
        if let field = options.truncation { value["truncation"] = .string(field) }
        if let field = options.user { value["user"] = .string(field) }
        if let field = options.systemMessageMode {
            switch field {
            case .system: value["systemMessageMode"] = .string("system")
            case .developer: value["systemMessageMode"] = .string("developer")
            case .remove: value["systemMessageMode"] = .string("remove")
            }
        }
        if let field = options.forceReasoning { value["forceReasoning"] = .bool(field) }
        if let field = options.contextManagement {
            value["contextManagement"] = .array(field.map {
                .object(["type": .string($0.type), "compactThreshold": .number($0.compactThreshold)])
            })
        }
        if let field = options.compactionTrigger { value["compactionTrigger"] = .bool(field) }
        if let field = options.allowedTools {
            var allowed: [String: JSONValue] = ["toolNames": .array(field.toolNames.map(JSONValue.string))]
            if let mode = field.mode { allowed["mode"] = .string(mode) }
            value["allowedTools"] = .object(allowed)
        }
        return ["openai": value]
    }
}

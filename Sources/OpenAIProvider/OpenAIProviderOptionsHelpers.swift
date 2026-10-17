import AISDKProvider

public extension OpenAIProvider {
    static func responsesOptions(
        _ options: OpenAILanguageModelResponsesOptions = .init(),
        extra: [String: JSONValue] = [:]
    ) -> SharedV4ProviderOptions {
        OpenAIOptions().responses(options, extra: extra)
    }

    func responsesOptions(
        _ options: OpenAILanguageModelResponsesOptions = .init(),
        extra: [String: JSONValue] = [:]
    ) -> SharedV4ProviderOptions {
        self.options.responses(options, extra: extra)
    }
}

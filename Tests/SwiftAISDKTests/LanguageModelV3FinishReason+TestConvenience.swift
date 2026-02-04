import AISDKProvider

extension LanguageModelV3FinishReason {
    static var stop: Self { .init(unified: .stop) }
    static var length: Self { .init(unified: .length) }
    static var contentFilter: Self { .init(unified: .contentFilter) }
    static var toolCalls: Self { .init(unified: .toolCalls) }
    static var error: Self { .init(unified: .error) }
    static var other: Self { .init(unified: .other) }
}


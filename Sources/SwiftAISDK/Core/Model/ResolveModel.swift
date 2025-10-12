public enum LanguageModelRef: Sendable {
    case id(String)
    case v2(any LanguageModelV2)
    // v3 будет добавлен позже
}

public enum ResolveModelError: Error {
    case unsupportedModelVersion
}

public struct ModelResolver {
    public init() {}

    public func resolveLanguageModel(_ model: LanguageModelRef) throws -> LanguageModelRef {
        // Пока просто возвращаем как есть, позже добавим адаптер V2→V3
        return model
    }
}


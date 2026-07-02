public struct LanguageModelV4FinishReason: Sendable, Codable, Equatable {
    public enum Unified: String, Sendable, Codable, Equatable {
        case stop
        case length
        case contentFilter = "content-filter"
        case toolCalls = "tool-calls"
        case error
        case other
    }

    public let unified: Unified
    public let raw: String?

    public init(unified: Unified, raw: String? = nil) {
        self.unified = unified
        self.raw = raw
    }
}

import AISDKProviderUtils

public struct OpenResponsesLanguageModelOptions: Codable, Sendable, Equatable {
    public enum ReasoningSummary: String, Codable, Sendable { case concise, detailed, auto }
    public var reasoningEffort: String?
    public var reasoningSummary: ReasoningSummary?

    public init(reasoningEffort: String? = nil, reasoningSummary: ReasoningSummary? = nil) {
        self.reasoningEffort = reasoningEffort
        self.reasoningSummary = reasoningSummary
    }
}

let openResponsesLanguageModelOptions = FlexibleSchema(
    Schema<OpenResponsesLanguageModelOptions>.codable(OpenResponsesLanguageModelOptions.self, jsonSchema: ["type": "object"])
)

import AISDKProvider
import AISDKProviderUtils

public struct AzureSpeechModelOptions: Sendable, Encodable, Equatable {
    public enum API: String, Sendable, Encodable { case openai, speech }
    public var api: API?
    public var style: String?
    public var styleDegree: Double?

    public init(api: API? = nil, style: String? = nil, styleDegree: Double? = nil) {
        self.api = api
        self.style = style
        self.styleDegree = styleDegree
    }
}

public struct AzureSpeechModelSpeechOptions: Sendable, Encodable, Equatable {
    public var style: String?
    public var styleDegree: Double?

    public init(style: String? = nil, styleDegree: Double? = nil) {
        self.style = style
        self.styleDegree = styleDegree
    }
}

private func speechSchema(api: Bool) -> JSONValue {
    var properties: JSONObject = [
        "style": ["type": "string", "minLength": 1],
        "styleDegree": ["type": "number", "minimum": 0.01, "maximum": 2]
    ]
    if api { properties["api"] = ["type": "string", "enum": ["openai", "speech"]] }
    return ["type": "object", "additionalProperties": false, "properties": .object(properties)]
}

private func speechOptions(_ value: Any, api: Bool) throws -> AzureSpeechModelOptions {
    let json = try jsonValue(from: value)
    guard case .object(let fields) = json else {
        throw SchemaValidationIssuesError(vendor: "azure", issues: "Expected speech options object")
    }
    let allowed: Set<String> = api ? ["api", "style", "styleDegree"] : ["style", "styleDegree"]
    guard Set(fields.keys).isSubset(of: allowed) else {
        throw SchemaValidationIssuesError(vendor: "azure", issues: "Unknown speech option")
    }
    var result = AzureSpeechModelOptions()
    if let value = fields["api"] {
        guard case .string(let name) = value, let api = AzureSpeechModelOptions.API(rawValue: name) else {
            throw SchemaValidationIssuesError(vendor: "azure", issues: "api must be openai or speech")
        }
        result.api = api
    }
    if let value = fields["style"] {
        guard case .string(let style) = value, !style.isEmpty else {
            throw SchemaValidationIssuesError(vendor: "azure", issues: "style must be a nonempty string")
        }
        result.style = style
    }
    if let value = fields["styleDegree"] {
        guard case .number(let degree) = value, degree.isFinite, degree >= 0.01, degree <= 2 else {
            throw SchemaValidationIssuesError(vendor: "azure", issues: "styleDegree must be between 0.01 and 2")
        }
        result.styleDegree = degree
    }
    return result
}

public let azureSpeechModelOptions = FlexibleSchema<AzureSpeechModelOptions>(Schema(
    jsonSchemaResolver: { speechSchema(api: true) },
    validator: { value in
        do { return .success(value: try speechOptions(value, api: true)) }
        catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

public let azureSpeechSpeechModelOptions = FlexibleSchema<AzureSpeechModelSpeechOptions>(Schema(
    jsonSchemaResolver: { speechSchema(api: false) },
    validator: { value in
        do {
            let options = try speechOptions(value, api: false)
            return .success(value: .init(style: options.style, styleDegree: options.styleDegree))
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

func maiVoiceModel(_ modelId: String) -> String? {
    ["mai-voice-2.1-flash": "MAI-Voice-2.1-Flash", "mai-voice-2.1": "MAI-Voice-2.1",
     "mai-voice-2-flash": "MAI-Voice-2-Flash", "mai-voice-2": "MAI-Voice-2"][modelId.lowercased()]
}

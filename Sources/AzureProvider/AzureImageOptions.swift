import AISDKProvider
import AISDKProviderUtils

public struct AzureImageModelOptions: Sendable, Encodable, Equatable {
    public enum API: String, Sendable, Encodable { case openai, mai }
    public var api: API?
    public var autoAspectRatio: Bool?
    public var webGrounding: Bool?

    public init(api: API? = nil, autoAspectRatio: Bool? = nil, webGrounding: Bool? = nil) {
        self.api = api
        self.autoAspectRatio = autoAspectRatio
        self.webGrounding = webGrounding
    }
}

public struct AzureImageModelMaiOptions: Sendable, Encodable, Equatable {
    public var autoAspectRatio: Bool?
    public var webGrounding: Bool?

    public init(autoAspectRatio: Bool? = nil, webGrounding: Bool? = nil) {
        self.autoAspectRatio = autoAspectRatio
        self.webGrounding = webGrounding
    }
}

private let maiProperties: JSONObject = [
    "autoAspectRatio": ["type": "boolean"], "webGrounding": ["type": "boolean"]
]

private func maiOptions(_ value: Any) throws -> AzureImageModelMaiOptions {
    let json = try jsonValue(from: value)
    guard case .object(let fields) = json else {
        throw SchemaValidationIssuesError(vendor: "azure", issues: "Expected image options object")
    }
    func boolean(_ key: String) throws -> Bool? {
        guard let value = fields[key] else { return nil }
        guard case .bool(let result) = value else {
            throw SchemaValidationIssuesError(vendor: "azure", issues: "\(key) must be a boolean")
        }
        return result
    }
    return try .init(autoAspectRatio: boolean("autoAspectRatio"), webGrounding: boolean("webGrounding"))
}

public let azureMaiImageModelOptions = FlexibleSchema<AzureImageModelMaiOptions>(Schema(
    jsonSchemaResolver: { ["type": "object", "properties": .object(maiProperties)] },
    validator: { value in
        do { return .success(value: try maiOptions(value)) }
        catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

public let azureImageModelOptions = FlexibleSchema<AzureImageModelOptions>(Schema(
    jsonSchemaResolver: {
        var properties = maiProperties
        properties["api"] = ["type": "string", "enum": ["openai", "mai"]]
        return ["type": "object", "properties": .object(properties)]
    },
    validator: { value in
        do {
            let mai = try maiOptions(value)
            let json = try jsonValue(from: value)
            var api: AzureImageModelOptions.API?
            if case .object(let fields) = json, let value = fields["api"] {
                guard case .string(let name) = value, let parsed = AzureImageModelOptions.API(rawValue: name) else {
                    throw SchemaValidationIssuesError(vendor: "azure", issues: "api must be openai or mai")
                }
                api = parsed
            }
            return .success(value: .init(api: api, autoAspectRatio: mai.autoAspectRatio, webGrounding: mai.webGrounding))
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

func isMaiImageModel(_ modelId: String) -> Bool {
    ["mai-image-2.5", "mai-image-2.5-flash", "mai-image-2.5-pro", "mai-image-2.6", "mai-image-2.6-flash"].contains(modelId.lowercased())
}

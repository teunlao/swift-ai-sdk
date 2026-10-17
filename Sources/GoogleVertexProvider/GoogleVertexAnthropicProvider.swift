import Foundation
import AISDKProvider
import AISDKProviderUtils
import AnthropicProvider

public typealias GoogleVertexAnthropicModelId = String

public struct GoogleVertexAnthropicProviderOptions: Sendable, Codable, Equatable {
    public var labels: [String: String]?
    public init(labels: [String: String]? = nil) { self.labels = labels }
}

private let vertexAnthropicOptions = FlexibleSchema(Schema<GoogleVertexAnthropicProviderOptions>(
    jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
        do {
            let json = try jsonValue(from: value)
            if case .object(let object) = json, object["labels"] == .null {
                throw SchemaValidationIssuesError(vendor: "vertex", issues: "labels must be a string record")
            }
            return .success(value: try JSONDecoder().decode(GoogleVertexAnthropicProviderOptions.self, from: JSONEncoder().encode(json)))
        } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
    }
))

public struct GoogleVertexAnthropicTools: Sendable {
    public init() {}
    public func bash20241022(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.bash20241022(options) }
    public func bash20250124(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.bash20250124(options) }
    public func textEditor20241022(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.textEditor20241022(options) }
    public func textEditor20250124(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.textEditor20250124(options) }
    public func textEditor20250429(_ options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.textEditor20250429(options) }
    public func textEditor20250728(_ args: AnthropicTextEditor20250728Args = .init(), options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.textEditor20250728(args, options: options) }
    public func computer20241022(_ args: AnthropicComputerOptions, options: ProviderDefinedToolFactoryOptions = .init()) -> Tool { anthropicTools.computer20241022(args, options: options) }
    public func webSearch20250305(_ args: AnthropicWebSearchOptions = .init(), callbacks: ProviderExecutedToolFactoryOptions = .init()) -> Tool { anthropicTools.webSearch20250305(args, callbacks: callbacks) }
    public func toolSearchRegex20251119(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool { anthropicTools.toolSearchRegex20251119(options) }
    public func toolSearchBm2520251119(_ options: ProviderExecutedToolFactoryOptions = .init()) -> Tool { anthropicTools.toolSearchBm2520251119(options) }
}

public let googleVertexAnthropicTools = GoogleVertexAnthropicTools()

public final class GoogleVertexAnthropicProvider: ProviderV4 {
    private let config: VertexPartnerConfig
    public let tools = googleVertexAnthropicTools
    init(settings: GoogleVertexAnthropicProviderSettings) { config = .init(settings) }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 { messages(modelId: modelId) }
    public func callAsFunction(_ modelId: String) -> AnthropicMessagesLanguageModel { messages(modelId: modelId) }
    public func chat(modelId: String) -> AnthropicMessagesLanguageModel { messages(modelId: modelId) }
    public func messages(modelId: String) -> AnthropicMessagesLanguageModel {
        let config = self.config
        return AnthropicMessagesLanguageModel(modelId: .init(rawValue: modelId), config: .init(
            provider: "googleVertex.anthropic.messages", baseURL: config.settings.baseURL ?? "",
            headers: {
                _ = try config.baseURL(.anthropic)
                return try await config.headers(callerOverridesAuth: true, api: .anthropic)
            }, fetch: config.settings.fetch,
            supportedUrls: { [:] },
            requestTransform: .init(
                buildURL: { _, streaming in "\(try config.baseURL(.anthropic))/\(modelId):\(streaming ? "streamRawPredict" : "rawPredict")" },
                transformBody: { body, _ in
                    var transformed = body
                    transformed.removeValue(forKey: "model")
                    transformed["anthropic_version"] = .string("vertex-2023-10-16")
                    return transformed
                },
                transformHeaders: { headers, providerOptions in
                    let options = try await parseProviderOptions(provider: "vertex", providerOptions: providerOptions, schema: vertexAnthropicOptions)
                    guard let labels = options?.labels,
                          !headers.contains(where: { $0.key.lowercased() == "x-vertex-ai-labels" && $0.value != nil }) else { return headers }
                    var transformed = headers
                    transformed["x-vertex-ai-labels"] = try JSONEncoder().encode(labels).base64EncodedString()
                    return transformed
                }
            ), supportsNativeStructuredOutput: false, supportsStrictTools: false
        ))
    }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}

public func createGoogleVertexAnthropic(settings: GoogleVertexAnthropicProviderSettings = .init()) -> GoogleVertexAnthropicProvider {
    .init(settings: settings)
}
public let googleVertexAnthropic = createGoogleVertexAnthropic()

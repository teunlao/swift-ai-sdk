import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum OpenResponsesHeaders: Sendable, ExpressibleByDictionaryLiteral {
    case values([String: String])
    case dynamic(@Sendable () throws -> [String: String])

    public init(dictionaryLiteral elements: (String, String)...) {
        self = .values(Dictionary(elements, uniquingKeysWith: { _, last in last }))
    }
    func resolve() throws -> [String: String] {
        switch self {
        case .values(let values): return values
        case .dynamic(let resolve): return try resolve()
        }
    }
}

public struct OpenResponsesProviderSettings: Sendable {
    public var url: String
    public var name: String
    public var apiKey: String?
    public var headers: OpenResponsesHeaders?
    public var fetch: FetchFunction?
    public var failedResponseHandler: ResponseHandler<APICallError>?
    public var getResponseErrorMetadata: (@Sendable (OpenResponsesResponseError) throws -> OpenResponsesResponseErrorMetadata)?
    public var strictResponseInput: Bool
    public var customToolId: String
    public var structuredOutputs: Bool
    public var userAgentSuffix: String?
    public var experimentalExtensions: [Experimental_OpenResponsesExtensionRegistration]

    public init(url: String, name: String, apiKey: String? = nil, headers: OpenResponsesHeaders? = nil, fetch: FetchFunction? = nil,
                failedResponseHandler: ResponseHandler<APICallError>? = nil,
                getResponseErrorMetadata: (@Sendable (OpenResponsesResponseError) throws -> OpenResponsesResponseErrorMetadata)? = nil,
                strictResponseInput: Bool = false, customToolId: String = "open-responses.custom", structuredOutputs: Bool = true,
                userAgentSuffix: String? = nil, experimentalExtensions: [Experimental_OpenResponsesExtensionRegistration] = []) {
        self.url = url
        self.name = name
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.failedResponseHandler = failedResponseHandler
        self.getResponseErrorMetadata = getResponseErrorMetadata
        self.strictResponseInput = strictResponseInput
        self.customToolId = customToolId
        self.structuredOutputs = structuredOutputs
        self.userAgentSuffix = userAgentSuffix
        self.experimentalExtensions = experimentalExtensions
    }
}

public final class OpenResponsesProvider: ProviderV4 {
    private let config: OpenResponsesConfig
    public let tools: OpenResponsesTools

    init(settings: OpenResponsesProviderSettings) throws {
        let extensions = try OpenResponsesExtensionRegistry(settings.experimentalExtensions)
        tools = OpenResponsesTools(customToolId: settings.customToolId)
        config = OpenResponsesConfig(
            provider: "\(settings.name).responses", providerOptionsName: settings.name, url: settings.url,
            headers: {
                var authorization: [String: String?] = [:]
                if let key = settings.apiKey, !key.isEmpty { authorization["Authorization"] = "Bearer \(key)" }
                let headers = combineHeaders(authorization, try settings.headers?.resolve().mapValues(Optional.some))
                return withUserAgentSuffix(headers, settings.userAgentSuffix ?? "ai-sdk-open-responses/\(OPEN_RESPONSES_VERSION)").mapValues(Optional.some)
            },
            fetch: settings.fetch, failedResponseHandler: settings.failedResponseHandler, getResponseErrorMetadata: settings.getResponseErrorMetadata,
            generateId: generateID, extensions: extensions, strictResponseInput: settings.strictResponseInput,
            customToolId: settings.customToolId, structuredOutputs: settings.structuredOutputs
        )
    }
    public func languageModel(modelId: String) -> any LanguageModelV4 { languageModel(modelId) }
    public func languageModel(_ modelId: String) -> OpenResponsesLanguageModel { .init(modelId: modelId, config: config) }
    public func callAsFunction(_ modelId: String) -> OpenResponsesLanguageModel { languageModel(modelId) }
    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .embeddingModel) }
    public func imageModel(modelId: String) throws -> any ImageModelV4 { throw NoSuchModelError(modelId: modelId, modelType: .imageModel) }
}

public func createOpenResponses(options: OpenResponsesProviderSettings) throws -> OpenResponsesProvider { try .init(settings: options) }

import Foundation
import AISDKProvider
import AISDKProviderUtils

public typealias GroundingMetadataSchema = JSONValue
public typealias UrlContextMetadataSchema = JSONValue
public typealias SafetyRatingSchema = JSONValue

public struct GoogleGenerativeAISharedMetadata: Sendable, Equatable {
    public let promptFeedback: JSONValue?
    public let groundingMetadata: GroundingMetadataSchema?
    public let urlContextMetadata: UrlContextMetadataSchema?
    public let safetyRatings: [SafetyRatingSchema]?
    public let usageMetadata: JSONValue?

    public init(
        promptFeedback: JSONValue? = nil,
        groundingMetadata: GroundingMetadataSchema? = nil,
        urlContextMetadata: UrlContextMetadataSchema? = nil,
        safetyRatings: [SafetyRatingSchema]? = nil,
        usageMetadata: JSONValue? = nil
    ) {
        self.promptFeedback = promptFeedback
        self.groundingMetadata = groundingMetadata
        self.urlContextMetadata = urlContextMetadata
        self.safetyRatings = safetyRatings
        self.usageMetadata = usageMetadata
    }
}

public final class GoogleGenerativeAILanguageModel: LanguageModelV3 {
    public struct Config: Sendable {
        public let provider: String
        public let baseURL: String
        public let headers: @Sendable () -> [String: String?]
        public let fetch: FetchFunction?
        public let generateId: @Sendable () -> String
        public let supportedUrls: @Sendable () -> [String: [NSRegularExpression]]

        public init(
            provider: String,
            baseURL: String,
            headers: @escaping @Sendable () -> [String: String?],
            fetch: FetchFunction?,
            generateId: @escaping @Sendable () -> String,
            supportedUrls: @escaping @Sendable () -> [String: [NSRegularExpression]]
        ) {
            self.provider = provider
            self.baseURL = baseURL
            self.headers = headers
            self.fetch = fetch
            self.generateId = generateId
            self.supportedUrls = supportedUrls
        }
    }

    private let modelIdentifier: GoogleGenerativeAIModelId
    private let config: Config

    public init(modelId: GoogleGenerativeAIModelId, config: Config) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }

    public var supportedUrls: [String: [NSRegularExpression]] {
        get async throws {
            config.supportedUrls()
        }
    }

    public func doGenerate(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3GenerateResult {
        fatalError("GoogleGenerativeAILanguageModel.doGenerate is not implemented yet")
    }

    public func doStream(options: LanguageModelV3CallOptions) async throws -> LanguageModelV3StreamResult {
        fatalError("GoogleGenerativeAILanguageModel.doStream is not implemented yet")
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

private let googleFilesRegex: NSRegularExpression = {
    try! NSRegularExpression(pattern: "^https?://" +
        "generativelanguage\\.googleapis\\.com/v1beta/files/.*$",
        options: [.caseInsensitive])
}()

private let youtubeWatchRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^https://(?:www\\.)?youtube\\.com/watch\\?v=[A-Za-z0-9_-]+(?:&[A-Za-z0-9_=&.-]*)?$",
        options: [.caseInsensitive]
    )
}()

private let youtubeShortRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^https://youtu\\.be/[A-Za-z0-9_-]+(?:\\?[A-Za-z0-9_=&.-]*)?$",
        options: [.caseInsensitive]
    )
}()

public struct GoogleProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: @Sendable () -> String

    public init(
        baseURL: String? = nil,
        apiKey: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: @escaping @Sendable () -> String = generateID
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
    }
}

public final class GoogleProvider: ProviderV3 {
    private let languageFactory: @Sendable (GoogleGenerativeAIModelId) -> GoogleGenerativeAILanguageModel
    private let embeddingFactory: @Sendable (GoogleGenerativeAIEmbeddingModelId) -> GoogleGenerativeAIEmbeddingModel
    private let imageFactory: @Sendable (GoogleGenerativeAIImageModelId, GoogleGenerativeAIImageSettings) -> GoogleGenerativeAIImageModel

    public let tools: GoogleTools

    init(
        language: @escaping @Sendable (GoogleGenerativeAIModelId) -> GoogleGenerativeAILanguageModel,
        embedding: @escaping @Sendable (GoogleGenerativeAIEmbeddingModelId) -> GoogleGenerativeAIEmbeddingModel,
        image: @escaping @Sendable (GoogleGenerativeAIImageModelId, GoogleGenerativeAIImageSettings) -> GoogleGenerativeAIImageModel,
        tools: GoogleTools
    ) {
        self.languageFactory = language
        self.embeddingFactory = embedding
        self.imageFactory = image
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageFactory(GoogleGenerativeAIModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(GoogleGenerativeAIEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(GoogleGenerativeAIImageModelId(rawValue: modelId), .init())
    }

    public func chat(modelId: GoogleGenerativeAIModelId) -> GoogleGenerativeAILanguageModel {
        languageFactory(modelId)
    }

    public func generativeAI(modelId: GoogleGenerativeAIModelId) -> GoogleGenerativeAILanguageModel {
        languageFactory(modelId)
    }

    public func image(modelId: GoogleGenerativeAIImageModelId, settings: GoogleGenerativeAIImageSettings = .init()) -> any ImageModelV3 {
        imageFactory(modelId, settings)
    }

    public func textEmbedding(modelId: GoogleGenerativeAIEmbeddingModelId) -> any EmbeddingModelV3<String> {
        embeddingFactory(modelId)
    }
}

public func createGoogleGenerativeAI(
    settings: GoogleProviderSettings = .init()
) -> GoogleProvider {
    let baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://generativelanguage.googleapis.com/v1beta"

    let headersClosure: @Sendable () -> [String: String?] = {
        let apiKey: String
        do {
            apiKey = try loadAPIKey(
                apiKey: settings.apiKey,
                environmentVariableName: "GOOGLE_GENERATIVE_AI_API_KEY",
                description: "Google Generative AI"
            )
        } catch {
            fatalError("Google Generative AI API key is missing: \(error)")
        }

        var baseHeaders: [String: String?] = [
            "x-goog-api-key": apiKey
        ]

        if let custom = settings.headers {
            for (key, value) in custom {
                baseHeaders[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            baseHeaders,
            "ai-sdk/google/\(GOOGLE_PROVIDER_VERSION)"
        )

        return withUA.mapValues { Optional($0) }
    }

    let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
        let baseRegex = try! NSRegularExpression(
            pattern: "^" + NSRegularExpression.escapedPattern(for: baseURL) + "/files/.*$",
            options: [.caseInsensitive]
        )

        return [
            "*": [baseRegex, youtubeWatchRegex, youtubeShortRegex]
        ]
    }

    let makeLanguageModel: @Sendable (GoogleGenerativeAIModelId) -> GoogleGenerativeAILanguageModel = { modelId in
        GoogleGenerativeAILanguageModel(
            modelId: modelId,
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.generative-ai",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch,
                generateId: settings.generateId,
                supportedUrls: supportedURLs
            )
        )
    }

    let makeEmbeddingModel: @Sendable (GoogleGenerativeAIEmbeddingModelId) -> GoogleGenerativeAIEmbeddingModel = { modelId in
        GoogleGenerativeAIEmbeddingModel(
            modelId: modelId,
            config: GoogleGenerativeAIEmbeddingConfig(
                provider: "google.generative-ai",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    let makeImageModel: @Sendable (GoogleGenerativeAIImageModelId, GoogleGenerativeAIImageSettings) -> GoogleGenerativeAIImageModel = { modelId, imageSettings in
        GoogleGenerativeAIImageModel(
            modelId: modelId,
            settings: imageSettings,
            config: GoogleGenerativeAIImageModelConfig(
                provider: "google.generative-ai",
                baseURL: baseURL,
                headers: headersClosure,
                fetch: settings.fetch
            )
        )
    }

    return GoogleProvider(
        language: makeLanguageModel,
        embedding: makeEmbeddingModel,
        image: makeImageModel,
        tools: googleTools
    )
}

public extension GoogleProvider {
    func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }
}

public let google = createGoogleGenerativeAI()

import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-provider.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private let googleVertexHTTPRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^https?:\\/\\/.*$",
        options: [.caseInsensitive]
    )
}()

private let googleVertexGCSRegex: NSRegularExpression = {
    try! NSRegularExpression(
        pattern: "^gs:\\/\\/.*$",
        options: [.caseInsensitive]
    )
}()

public struct GoogleVertexProviderSettings: Sendable {
    public var location: String?
    public var project: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: @Sendable () -> String
    public var baseURL: String?

    public init(
        location: String? = nil,
        project: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: @escaping @Sendable () -> String = generateID,
        baseURL: String? = nil
    ) {
        self.location = location
        self.project = project
        self.headers = headers
        self.fetch = fetch
        self.generateId = generateId
        self.baseURL = baseURL
    }
}

public final class GoogleVertexProvider: ProviderV3 {
    private let languageFactory: @Sendable (GoogleVertexModelId) -> GoogleGenerativeAILanguageModel
    private let embeddingFactory: @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel
    private let imageFactory: @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel

    public let tools: GoogleVertexTools

    init(
        language: @escaping @Sendable (GoogleVertexModelId) -> GoogleGenerativeAILanguageModel,
        embedding: @escaping @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel,
        image: @escaping @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel,
        tools: GoogleVertexTools
    ) {
        self.languageFactory = language
        self.embeddingFactory = embedding
        self.imageFactory = image
        self.tools = tools
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV3 {
        languageFactory(GoogleVertexModelId(rawValue: modelId))
    }

    public func textEmbeddingModel(modelId: String) throws -> any EmbeddingModelV3<String> {
        embeddingFactory(GoogleVertexEmbeddingModelId(rawValue: modelId))
    }

    public func imageModel(modelId: String) throws -> any ImageModelV3 {
        imageFactory(GoogleVertexImageModelId(rawValue: modelId))
    }

    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV3 {
        try languageModel(modelId: modelId)
    }

    // MARK: - Convenience Accessors

    public func chat(modelId: GoogleVertexModelId) -> GoogleGenerativeAILanguageModel {
        languageFactory(modelId)
    }

    public func textEmbedding(modelId: GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel {
        embeddingFactory(modelId)
    }

    public func image(modelId: GoogleVertexImageModelId) -> GoogleVertexImageModel {
        imageFactory(modelId)
    }
}

public func createGoogleVertex(settings: GoogleVertexProviderSettings = .init()) -> GoogleVertexProvider {
    let loadProject: () throws -> String = {
        try loadSetting(
            settingValue: settings.project,
            environmentVariableName: "GOOGLE_VERTEX_PROJECT",
            settingName: "project",
            description: "Google Vertex project"
        )
    }

    let loadLocation: () throws -> String = {
        try loadSetting(
            settingValue: settings.location,
            environmentVariableName: "GOOGLE_VERTEX_LOCATION",
            settingName: "location",
            description: "Google Vertex location"
        )
    }

    let resolvedBaseURL: String = {
        if let custom = withoutTrailingSlash(settings.baseURL) {
            return custom
        }

        do {
            let location = try loadLocation()
            let project = try loadProject()
            let hostPrefix = location == "global" ? "" : "\(location)-"
            let baseHost = "\(hostPrefix)aiplatform.googleapis.com"
            return "https://\(baseHost)/v1beta1/projects/\(project)/locations/\(location)/publishers/google"
        } catch {
            fatalError("Google Vertex configuration is missing: \(error)")
        }
    }()

    let headersClosure: @Sendable () -> [String: String?] = {
        var computed: [String: String?] = [:]
        if let provided = settings.headers {
            for (key, value) in provided {
                computed[key] = value
            }
        }

        let withUA = withUserAgentSuffix(
            computed.compactMapValues { $0 },
            "ai-sdk/google-vertex/\(GOOGLE_VERTEX_VERSION)"
        )

        return withUA.mapValues { Optional($0) }
    }

    let supportedURLs: @Sendable () -> [String: [NSRegularExpression]] = {
        ["*": [googleVertexHTTPRegex, googleVertexGCSRegex]]
    }

    let fetch = settings.fetch
    let generateId = settings.generateId

    let languageFactory: @Sendable (GoogleVertexModelId) -> GoogleGenerativeAILanguageModel = { modelId in
        GoogleGenerativeAILanguageModel(
            modelId: GoogleGenerativeAIModelId(rawValue: modelId.rawValue),
            config: GoogleGenerativeAILanguageModel.Config(
                provider: "google.vertex.chat",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch,
                generateId: generateId,
                supportedUrls: supportedURLs
            )
        )
    }

    let embeddingFactory: @Sendable (GoogleVertexEmbeddingModelId) -> GoogleVertexEmbeddingModel = { modelId in
        GoogleVertexEmbeddingModel(
            modelId: modelId,
            config: GoogleVertexEmbeddingConfig(
                provider: "google.vertex.embedding",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch
            )
        )
    }

    let imageFactory: @Sendable (GoogleVertexImageModelId) -> GoogleVertexImageModel = { modelId in
        GoogleVertexImageModel(
            modelId: modelId,
            config: GoogleVertexImageModelConfig(
                provider: "google.vertex.image",
                baseURL: resolvedBaseURL,
                headers: headersClosure,
                fetch: fetch,
                currentDate: { Date() }
            )
        )
    }

    return GoogleVertexProvider(
        language: languageFactory,
        embedding: embeddingFactory,
        image: imageFactory,
        tools: googleVertexTools
    )
}

public let googleVertex = createGoogleVertex()

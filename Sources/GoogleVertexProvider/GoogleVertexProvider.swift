import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-provider.ts
// Upstream commit: f5b2b5ef4
//===----------------------------------------------------------------------===//

private let GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL = "https://aiplatform.googleapis.com/v1/publishers/google"

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

private func defaultGoogleVertexFetchFunction() -> FetchFunction {
    { request in
        let session = URLSession.shared

        if #available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *) {
            let (bytes, response) = try await session.bytes(for: request)
            let stream = AsyncThrowingStream<Data, Error> { continuation in
                Task {
                    var buffer = Data()
                    buffer.reserveCapacity(16_384)

                    do {
                        for try await byte in bytes {
                            buffer.append(byte)

                            if buffer.count >= 16_384 {
                                continuation.yield(buffer)
                                buffer.removeAll(keepingCapacity: true)
                            }
                        }

                        if !buffer.isEmpty {
                            continuation.yield(buffer)
                        }

                        continuation.finish()
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
            }

            return FetchResponse(body: .stream(stream), urlResponse: response)
        } else {
            let (data, response) = try await session.data(for: request)
            return FetchResponse(body: .data(data), urlResponse: response)
        }
    }
}

private func createExpressModeFetch(
    apiKey: String,
    customFetch: FetchFunction?
) -> FetchFunction {
    let baseFetch = customFetch ?? defaultGoogleVertexFetchFunction()

    return { request in
        var modified = request
        var headers = modified.allHTTPHeaderFields ?? [:]
        for key in headers.keys where key.lowercased() == "x-goog-api-key" {
            headers.removeValue(forKey: key)
        }
        headers["x-goog-api-key"] = apiKey
        modified.allHTTPHeaderFields = headers
        return try await baseFetch(modified)
    }
}

public struct GoogleVertexProviderSettings: Sendable {
    /// Optional. The API key for the Google Cloud project. If provided, the provider will use express mode with API key authentication.
    /// Defaults to the value of the `GOOGLE_VERTEX_API_KEY` environment variable.
    public var apiKey: String?

    public var location: String?
    public var project: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: @Sendable () -> String
    public var baseURL: String?

    public init(
        apiKey: String? = nil,
        location: String? = nil,
        project: String? = nil,
        headers: [String: String]? = nil,
        fetch: FetchFunction? = nil,
        generateId: @escaping @Sendable () -> String = generateID,
        baseURL: String? = nil
    ) {
        self.apiKey = apiKey
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
    let apiKey = loadOptionalSetting(
        settingValue: settings.apiKey,
        environmentVariableName: "GOOGLE_VERTEX_API_KEY"
    )

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
        if apiKey != nil {
            return withoutTrailingSlash(settings.baseURL) ?? GOOGLE_VERTEX_EXPRESS_MODE_BASE_URL
        }

        do {
            let location = try loadLocation()
            let project = try loadProject()
            let hostPrefix = location == "global" ? "" : "\(location)-"
            let baseHost = "\(hostPrefix)aiplatform.googleapis.com"
            return withoutTrailingSlash(settings.baseURL)
                ?? "https://\(baseHost)/v1beta1/projects/\(project)/locations/\(location)/publishers/google"
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

    let fetch: FetchFunction? = {
        guard let apiKey else { return settings.fetch }
        return createExpressModeFetch(apiKey: apiKey, customFetch: settings.fetch)
    }()

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

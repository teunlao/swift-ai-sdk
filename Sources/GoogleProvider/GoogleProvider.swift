import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleProviderSettings: Sendable {
    public var baseURL: String?
    public var apiKey: String?
    public var headers: [String: String]?
    public var fetch: FetchFunction?
    public var generateId: @Sendable () -> String
    public var name: String?
    public var webSocket: GoogleWebSocketFactory?
    public init(baseURL: String? = nil, apiKey: String? = nil, headers: [String: String]? = nil, fetch: FetchFunction? = nil, generateId: @escaping @Sendable () -> String = generateID, name: String? = nil, webSocket: GoogleWebSocketFactory? = nil) {
        self.baseURL = baseURL; self.apiKey = apiKey; self.headers = headers; self.fetch = fetch
        self.generateId = generateId; self.name = name; self.webSocket = webSocket
    }
}

public final class GoogleProvider: ProviderV4 {
    private let settings: GoogleProviderSettings
    private let baseURL: String
    private let name: String
    private let headers: @Sendable () throws -> [String: String?]
    public let tools = googleTools
    init(settings: GoogleProviderSettings) {
        self.settings = settings
        self.baseURL = withoutTrailingSlash(settings.baseURL) ?? "https://generativelanguage.googleapis.com/v1beta"
        self.name = settings.name ?? "google.generative-ai"
        self.headers = {
            let headers = combineHeaders(["x-goog-api-key": try loadAPIKey(apiKey: settings.apiKey, environmentVariableName: "GOOGLE_GENERATIVE_AI_API_KEY", description: "Google Generative AI")], settings.headers?.mapValues { Optional($0) })
            return withUserAgentSuffix(headers, "ai-sdk-google/\(GOOGLE_PROVIDER_VERSION)").mapValues { Optional($0) }
        }
    }

    public func languageModel(modelId: String) throws -> any LanguageModelV4 { chat(modelId: .init(rawValue: modelId)) }
    public func chat(modelId: GoogleModelId) -> GoogleLanguageModel {
        let base = baseURL
        return .init(modelId: modelId, config: .init(provider: name, baseURL: base, headers: headers, fetch: settings.fetch, generateId: settings.generateId, supportedUrls: { googleSupportedURLs(baseURL: base, modelId: modelId.rawValue) }))
    }
    public func languageModel(modelId: GoogleModelId) -> GoogleLanguageModel { chat(modelId: modelId) }
    public func callAsFunction(_ modelId: String) throws -> any LanguageModelV4 { try languageModel(modelId: modelId) }

    public func embeddingModel(modelId: String) throws -> any EmbeddingModelV4 { embedding(modelId: .init(rawValue: modelId)) }
    public func embedding(modelId: GoogleEmbeddingModelId) -> any EmbeddingModelV4 { GoogleEmbeddingModel(modelId: modelId, config: .init(provider: name, baseURL: baseURL, headers: headers, fetch: settings.fetch)) }
    public func embeddingModel(modelId: GoogleEmbeddingModelId) -> any EmbeddingModelV4 { embedding(modelId: modelId) }

    public func imageModel(modelId: String) throws -> any ImageModelV4 { image(modelId: .init(rawValue: modelId)) }
    public func image(modelId: GoogleImageModelId, settings: GoogleImageSettings = .init()) -> any ImageModelV4 {
        GoogleImageModel(modelId: modelId, settings: settings, config: .init(provider: name, baseURL: baseURL, headers: headers, fetch: self.settings.fetch, generateId: self.settings.generateId))
    }
    public func imageModel(modelId: GoogleImageModelId, settings: GoogleImageSettings = .init()) -> any ImageModelV4 { image(modelId: modelId, settings: settings) }
    public func video(modelId: GoogleVideoModelId) -> GoogleVideoModel { .init(modelId: modelId, config: .init(provider: name, baseURL: baseURL, headers: headers, fetch: settings.fetch, generateId: settings.generateId)) }
    public func videoModel(modelId: GoogleVideoModelId) -> GoogleVideoModel { video(modelId: modelId) }
    public func videoModel(modelId: String) throws -> GoogleVideoModel { video(modelId: .init(rawValue: modelId)) }

    public func speech(modelId: String) -> GoogleSpeechModel { .init(modelId: modelId, config: .init(provider: "\(name).speech", baseURL: baseURL, headers: headers, fetch: settings.fetch)) }
    public func speechModel(modelId: String) throws -> (any SpeechModelV4)? { speech(modelId: modelId) }
    public func transcription(modelId: String) -> GoogleTranscriptionModel { .init(modelId: modelId, config: .init(provider: "\(name).transcription", baseURL: baseURL, headers: headers, fetch: settings.fetch, webSocket: settings.webSocket)) }
    public func transcriptionModel(modelId: String) throws -> (any TranscriptionModelV4)? { transcription(modelId: modelId) }
    public func files() throws -> (any FilesV4)? { GoogleFiles(config: .init(provider: name, baseURL: baseURL, headers: headers, fetch: settings.fetch)) }
    public func interactions(modelId: GoogleInteractionsModelId) -> GoogleInteractionsLanguageModel { .init(modelId: modelId.rawValue, config: .init(provider: "\(name).interactions", baseURL: baseURL, headers: headers, fetch: settings.fetch, generateId: settings.generateId)) }
    public func interactions(_ input: GoogleInteractionsModelInput) -> GoogleInteractionsLanguageModel { .init(input: input, config: .init(provider: "\(name).interactions", baseURL: baseURL, headers: headers, fetch: settings.fetch, generateId: settings.generateId)) }
}

public func createGoogle(settings: GoogleProviderSettings = .init()) -> GoogleProvider { .init(settings: settings) }
public let google = createGoogle()

private func googleSupportedURLs(baseURL: String, modelId: String) -> [String: [NSRegularExpression]] {
    var urls: [String: [NSRegularExpression]] = ["*": [
        try! .init(pattern: "^https://generativelanguage\\.googleapis\\.com/v1beta/files/.*$"),
        try! .init(pattern: "^\(baseURL)/files/.*$"),
        try! .init(pattern: "^https://(?:www\\.)?youtube\\.com/watch\\?v=[\\w-]+(?:&[\\w=&.-]*)?$"),
        try! .init(pattern: "^https://youtu\\.be/[\\w-]+(?:\\?[\\w=&.-]*)?$")
    ]]
    if googleModelMatches(modelId, "(^|/)gemini-") && !googleModelMatches(modelId, "(^|/)gemini-2\\.0") {
        let external = try! NSRegularExpression(pattern: "^https://.*$")
        for type in ["text/html", "text/css", "text/plain", "text/xml", "text/csv", "text/rtf", "text/javascript", "application/json", "application/pdf", "image/bmp", "image/jpeg", "image/png", "image/webp", "video/mp4", "video/mpeg", "video/quicktime", "video/avi", "video/x-flv", "video/mpg", "video/webm", "video/wmv", "video/3gpp"] { urls[type] = [external] }
    }
    return urls
}

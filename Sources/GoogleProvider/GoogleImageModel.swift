import Foundation
import AISDKProvider
import AISDKProviderUtils

struct GoogleImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let generateId: @Sendable () -> String
    let currentDate: @Sendable () -> Date
    init(provider: String, baseURL: String, headers: @escaping @Sendable () throws -> [String: String?], fetch: FetchFunction?, generateId: @escaping @Sendable () -> String = generateID, currentDate: @escaping @Sendable () -> Date = { Date() }) {
        self.provider = provider; self.baseURL = baseURL; self.headers = headers; self.fetch = fetch
        self.generateId = generateId; self.currentDate = currentDate
    }
}

final class GoogleImageModel: ImageModelV4 {
    private let modelIdentifier: GoogleImageModelId
    private let settings: GoogleImageSettings
    private let config: GoogleImageModelConfig
    init(modelId: GoogleImageModelId, settings: GoogleImageSettings, config: GoogleImageModelConfig) {
        self.modelIdentifier = modelId; self.settings = settings; self.config = config
    }
    var modelId: String { modelIdentifier.rawValue }
    var provider: String { config.provider }
    var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(settings.maxImagesPerCall ?? 1) }
    var supportsFileInputs: Bool? {
        get async throws { ["gemini-2.5-flash-image", "gemini-3-pro-image-preview", "gemini-3.1-flash-image-preview", "gemini-nano-banana-2.1"].contains(modelId) ? true : nil }
    }
    var supportsMaskInputs: Bool? { get async throws { try await supportsFileInputs == true ? false : nil } }

    func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        guard modelId.hasPrefix("gemini-") else { throw UnsupportedFunctionalityError(functionality: "Google image models other than Gemini are no longer supported. Use a model ID that starts with `gemini-`.") }
        if options.mask != nil { throw InvalidArgumentError(argument: "mask", message: "Gemini image models do not support mask-based image editing.") }
        var warnings: [SharedV4Warning] = []
        if options.size != nil { warnings.append(.unsupported(feature: "size", details: "This model does not support the `size` option. Use `aspectRatio` instead.")) }
        var content: [LanguageModelV4UserMessagePart] = []
        if let prompt = options.prompt { content.append(.text(.init(text: prompt))) }
        for file in options.files ?? [] {
            switch file {
            case .url(let string, _):
                guard let url = URL(string: string), url.scheme != nil else { throw InvalidArgumentError(argument: "files", message: "Invalid file URL: \(string)") }
                content.append(.file(.init(data: .url(url), mediaType: "image/*")))
            case .file(let type, let data, _):
                let value: SharedV4FileData
                switch data { case .base64(let string): value = .base64(string); case .binary(let bytes): value = .data(bytes) }
                content.append(.file(.init(data: value, mediaType: type)))
            }
        }
        var google = options.providerOptions?["google"] ?? [:]
        let search = google.removeValue(forKey: "googleSearch")
        google["responseModalities"] = .array([.string("IMAGE")])
        if let ratio = options.aspectRatio {
            var image: [String: JSONValue] = [:]
            if case .object(let object) = google["imageConfig"] { image = object }
            image["aspectRatio"] = .string(ratio)
            google["imageConfig"] = .object(image)
        }
        var tools: [LanguageModelV4Tool]?
        if let search {
            let args = try validateGoogleSearchArgs(search)
            tools = [.provider(.init(id: "google.google_search", name: "google_search", args: args))]
        }
        let language = GoogleLanguageModel(modelId: .init(rawValue: modelId), config: .init(provider: provider, baseURL: config.baseURL, headers: config.headers, fetch: config.fetch, generateId: config.generateId))
        let result = try await language.doGenerate(options: .init(prompt: [.user(content: content, providerOptions: nil)], seed: options.seed, tools: tools, abortSignal: options.abortSignal, headers: options.headers, providerOptions: ["google": google]))
        var images: [String] = []
        for part in result.content {
            if case .file(let file) = part, file.mediaType.hasPrefix("image/") {
                switch file.data { case .base64(let string): images.append(string); case .data(let bytes): images.append(bytes.base64EncodedString()); case .url: break }
            }
        }
        var metadata = result.providerMetadata?["google"] ?? [:]
        metadata["finishReason"] = result.finishReason.raw.map(JSONValue.string) ?? .null
        return .init(images: .base64(images), isRetryable: result.finishReason.unified == .contentFilter ? false : nil, warnings: warnings, providerMetadata: ["google": .init(images: images.map { _ in .object([:]) }, additionalData: .object(metadata))], response: .init(timestamp: config.currentDate(), modelId: modelId, headers: result.response?.headers), usage: .init(inputTokens: result.usage.inputTokens.total, outputTokens: result.usage.outputTokens.total, totalTokens: (result.usage.inputTokens.total ?? 0) + (result.usage.outputTokens.total ?? 0)))
    }
}

func validateGoogleSearchArgs(_ value: JSONValue) throws -> [String: JSONValue] {
    guard case .object(var object) = value else { throw InvalidArgumentError(argument: "googleSearch", message: "googleSearch must be an object") }
    if let types = object["searchTypes"] {
        guard case .object(let fields) = types else { throw InvalidArgumentError(argument: "searchTypes", message: "searchTypes must be an object") }
        var parsed: [String: JSONValue] = [:]
        for key in ["webSearch", "imageSearch"] {
            if let value = fields[key] {
                guard case .object = value else { throw InvalidArgumentError(argument: key, message: "\(key) must be an object") }
                parsed[key] = .object([:])
            }
        }
        object["searchTypes"] = .object(parsed)
    }
    if let range = object["timeRangeFilter"] {
        guard case .object(let fields) = range, case .string = fields["startTime"], case .string = fields["endTime"] else { throw InvalidArgumentError(argument: "timeRangeFilter", message: "timeRangeFilter requires startTime and endTime") }
        object["timeRangeFilter"] = .object(["startTime": fields["startTime"]!, "endTime": fields["endTime"]!])
    }
    return object
}

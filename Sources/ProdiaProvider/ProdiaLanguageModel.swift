import Foundation
import AISDKProvider
import AISDKProviderUtils

public final class ProdiaLanguageModel: LanguageModelV4 {
    public var specificationVersion: String { "v4" }
    public var provider: String { config.provider }
    public var modelId: String { identifier.rawValue }
    public var supportedUrls: [String: [NSRegularExpression]] { [:] }
    private let identifier: ProdiaLanguageModelId
    private let config: ProdiaModelConfig

    init(modelId: ProdiaLanguageModelId, config: ProdiaModelConfig) {
        self.identifier = modelId
        self.config = config
    }

    public func doGenerate(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []
        for (feature, present) in [
            ("temperature", options.temperature != nil), ("topP", options.topP != nil), ("topK", options.topK != nil),
            ("seed", options.seed != nil), ("maxOutputTokens", options.maxOutputTokens != nil),
            ("stopSequences", options.stopSequences != nil), ("presencePenalty", options.presencePenalty != nil),
            ("frequencyPenalty", options.frequencyPenalty != nil), ("tools", options.tools?.isEmpty == false),
            ("toolChoice", options.toolChoice != nil),
        ] where present { warnings.append(.unsupported(feature: feature, details: nil)) }
        if let format = options.responseFormat, format != .text { warnings.append(.unsupported(feature: "responseFormat", details: nil)) }
        if isCustomReasoning(options.reasoning) {
            warnings.append(.unsupported(feature: "reasoning", details: "This provider does not support reasoning configuration."))
        }
        let parsed = try await parseProviderOptions(provider: "prodia", providerOptions: options.providerOptions,
                                                   schema: prodiaLanguageModelOptionsSchema)
        var system = ""
        var prompt = ""
        var userParts: [LanguageModelV4UserMessagePart] = []
        for message in options.prompt {
            if case .system(let text, _) = message { system = text }
        }
        for message in options.prompt.reversed() {
            if case .user(let content, _) = message { userParts = content; break }
        }
        for part in userParts {
            if case .text(let value) = part { prompt += (prompt.isEmpty ? "" : "\n") + value.text }
        }
        if !system.isEmpty { prompt = system + "\n" + prompt }
        var imageBytes: Data?
        var imageMediaType = "image/png"
        for part in userParts {
            guard case .file(let file) = part, getTopLevelMediaType(file.mediaType) == "image" else { continue }
            switch file.data {
            case .reference:
                throw UnsupportedFunctionalityError(functionality: "file parts with provider references")
            case .text:
                throw UnsupportedFunctionalityError(functionality: "text file parts")
            case .data(let data): imageBytes = data
            case .base64(let value): imageBytes = try convertBase64ToData(value)
            case .url(let url, let originalUrl):
                let address = originalUrl ?? url.absoluteString
                if url.scheme == "data" {
                    imageBytes = try await downloadBlob(url: address, isAborted: options.abortSignal, fetch: config.fetch).data
                } else {
                    let response = try await fetchUntrustedUrl(url: address, isAborted: options.abortSignal, fetch: config.fetch)
                    imageBytes = try await response.body.collectData()
                }
            }
            if isFullMediaType(file.mediaType) { imageMediaType = file.mediaType }
            else if let imageBytes, let detected = detectMediaType(data: imageBytes, topLevelType: getTopLevelMediaType(file.mediaType)) {
                imageMediaType = detected
            }
            break
        }
        var jobConfig: JSONObject = ["prompt": .string(prompt), "include_messages": .bool(true)]
        if let ratio = parsed?.aspectRatio { jobConfig["aspect_ratio"] = .string(ratio) }
        let job: JSONValue = .object(["type": .string(modelId), "config": .object(jobConfig)])
        let now = config.currentDate()
        let headers = combineHeaders(try await config.headers(), options.headers?.mapValues { Optional($0) },
                                     ["Accept": "multipart/form-data"]).compactMapValues { $0 }
        var form = MultipartFormDataBuilder()
        form.appendFile(name: "job", filename: "job.json", contentType: "application/json", data: try JSONEncoder().encode(job))
        if let imageBytes {
            let extensions = ["image/png": ".png", "image/jpeg": ".jpg", "image/webp": ".webp"]
            form.appendFile(name: "input", filename: "input" + (extensions[imageMediaType] ?? ""), contentType: imageMediaType, data: imageBytes)
        }
        let response = try await postToAPI(
            url: "\(config.baseURL)/job?price=true", headers: headers,
            body: .init(content: .multipartFormData(form), values: job),
            failedResponseHandler: prodiaFailedResponseHandler, successfulResponseHandler: prodiaLanguageResponseHandler,
            isAborted: options.abortSignal, fetch: config.fetch
        )
        var content: [LanguageModelV4Content] = []
        if let text = response.value.text { content.append(.text(.init(text: text))) }
        content += response.value.files.map { .file(.init(mediaType: $0.mediaType, data: .data($0.body))) }
        return .init(content: content, finishReason: .init(unified: .stop), usage: .init(),
                     providerMetadata: ["prodia": response.value.job.metadata],
                     response: .init(timestamp: now, modelId: modelId, headers: response.responseHeaders), warnings: warnings)
    }

    public func doStream(options: LanguageModelV4CallOptions) async throws -> LanguageModelV4StreamResult {
        let result = try await doGenerate(options: options)
        let stream = AsyncThrowingStream<LanguageModelV4StreamPart, Error> { continuation in
            continuation.yield(.streamStart(warnings: result.warnings))
            continuation.yield(.responseMetadata(id: nil, modelId: result.response?.modelId, timestamp: result.response?.timestamp))
            for part in result.content {
                switch part {
                case .text(let text):
                    let id = generateID()
                    continuation.yield(.textStart(id: id, providerMetadata: nil))
                    continuation.yield(.textDelta(id: id, delta: text.text, providerMetadata: nil))
                    continuation.yield(.textEnd(id: id, providerMetadata: nil))
                case .file(let file): continuation.yield(.file(file))
                default: break
                }
            }
            continuation.yield(.finish(finishReason: result.finishReason, usage: result.usage, providerMetadata: result.providerMetadata))
            continuation.finish()
        }
        return .init(stream: stream, response: .init(headers: result.response?.headers))
    }
}

private struct ProdiaLanguageResponse: Sendable {
    let job: ProdiaJobResult
    let text: String?
    let files: [ProdiaMultipartPart]
}

private let prodiaLanguageResponseHandler: ResponseHandler<ProdiaLanguageResponse> = { input in
    let multipart = try await prodiaMultipartResponseHandler(input)
    var text: String?
    var files: [ProdiaMultipartPart] = []
    for part in multipart.value.parts {
        guard !part.disposition.contains("name=\"job\""), part.disposition.contains("name=\"output\"") else { continue }
        if part.mediaType.hasPrefix("text/") || part.disposition.contains(".txt") { text = String(decoding: part.body, as: UTF8.self) }
        else if part.mediaType.hasPrefix("image/") { files.append(part) }
    }
    return .init(value: .init(job: multipart.value.job, text: text, files: files), responseHeaders: multipart.responseHeaders)
}

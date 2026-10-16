import Foundation
import AISDKProvider
import AISDKProviderUtils

struct LumaImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

private struct LumaGenerationResponse: Decodable, Sendable {
    enum State: String, Decodable { case queued, dreaming, completed, failed }
    struct Assets: Decodable, Sendable { let image: String }
    let id: String
    let state: State
    let failure_reason: String?
    let assets: Assets?
}

private let lumaGenerationResponseSchema = FlexibleSchema(Schema<LumaGenerationResponse>.codable(
    LumaGenerationResponse.self, jsonSchema: .object(["type": .string("object")])
))

public final class LumaImageModel: ImageModelV4 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV4MaxImagesPerCall { .value(1) }
    public var supportsFileInputs: Bool? { ["photon-1", "photon-flash-1"].contains(modelId) ? true : nil }
    public var supportsMaskInputs: Bool? { supportsFileInputs == true ? false : nil }
    public let pollIntervalMillis = 500
    public let maxPollAttempts = 120
    private let modelIdentifier: LumaImageModelId
    private let config: LumaImageModelConfig

    init(modelId: LumaImageModelId, config: LumaImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV4CallOptions) async throws -> ImageModelV4GenerateResult {
        var warnings: [SharedV4Warning] = []
        if options.seed != nil { warnings.append(.unsupported(feature: "seed", details: "This model does not support the `seed` option.")) }
        if options.size != nil { warnings.append(.unsupported(feature: "size", details: "This model does not support the `size` option. Use `aspectRatio` instead.")) }
        let parsed = try await parseProviderOptions(provider: "luma", providerOptions: options.providerOptions, schema: lumaImageModelOptionsSchema)
        var providerOptions: [String: JSONValue] = [:]
        if case .object(let values) = parsed { providerOptions = values }
        let interval = number(providerOptions.removeValue(forKey: "pollIntervalMillis")) ?? Double(pollIntervalMillis)
        let attempts = number(providerOptions.removeValue(forKey: "maxPollAttempts")) ?? Double(maxPollAttempts)
        let referenceType: LumaReferenceType
        if case .string(let value) = providerOptions.removeValue(forKey: "referenceType") { referenceType = LumaReferenceType(rawValue: value)! }
        else { referenceType = .image }
        let imageConfigs: [LumaImageConfig]
        if let value = providerOptions.removeValue(forKey: "images"), value != .null {
            imageConfigs = try JSONDecoder().decode([LumaImageConfig].self, from: JSONEncoder().encode(value))
        } else { imageConfigs = [] }
        var body = try editingOptions(files: options.files ?? [], mask: options.mask, referenceType: referenceType, imageConfigs: imageConfigs)
        body["model"] = .string(modelId)
        if let prompt = options.prompt { body["prompt"] = .string(prompt) }
        if let aspectRatio = options.aspectRatio, !aspectRatio.isEmpty { body["aspect_ratio"] = .string(aspectRatio) }
        body.merge(providerOptions) { _, value in value }
        let timestamp = config.currentDate()
        let headers = combineHeaders(try config.headers(), options.headers?.mapValues { Optional($0) }).compactMapValues { $0 }
        let response = try await postJsonToAPI(
            url: generationsURL(), headers: headers, body: JSONValue.object(body),
            failedResponseHandler: lumaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: lumaGenerationResponseSchema),
            isAborted: options.abortSignal, fetch: config.fetch
        )
        let imageURL = try await pollForImageURL(id: response.value.id, headers: headers, abortSignal: options.abortSignal, interval: interval, attempts: attempts)
        let image = try await getFromAPI(
            url: imageURL,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal, fetch: config.fetch,
            validateUrl: true, trustedOrigin: config.baseURL
        ).value
        return .init(images: .binary([image]), warnings: warnings, response: .init(timestamp: timestamp, modelId: modelId, headers: response.responseHeaders))
    }

    private func pollForImageURL(id: String, headers: [String: String], abortSignal: (@Sendable () -> Bool)?, interval: Double, attempts: Double) async throws -> String {
        var index = 0
        while Double(index) < attempts {
            let result = try await getFromAPI(
                url: generationsURL(id), headers: headers,
                failedResponseHandler: lumaFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: lumaGenerationResponseSchema),
                isAborted: abortSignal, fetch: config.fetch
            ).value
            switch result.state {
            case .completed:
                guard let image = result.assets?.image, !image.isEmpty else {
                    throw InvalidResponseDataError(data: result, message: "Image generation completed but no image was found.")
                }
                return image
            case .failed: throw InvalidResponseDataError(data: result, message: "Image generation failed.")
            case .queued, .dreaming: try await delay(Int(interval), abortSignal: abortSignal)
            }
            index += 1
        }
        throw LumaImageModelError(message: "Image generation timed out after \(maxPollAttempts) attempts.")
    }

    private func editingOptions(files: [ImageModelV4File], mask: ImageModelV4File?, referenceType: LumaReferenceType, imageConfigs: [LumaImageConfig]) throws -> [String: JSONValue] {
        if mask != nil {
            throw LumaImageModelError(message: "Luma AI does not support mask-based image editing. Use the prompt to describe the changes you want to make, along with `prompt.images` containing the source image URL.")
        }
        if files.isEmpty { return [:] }
        let urls = try files.map { file -> String in
            guard case .url(let url, _) = file else {
                throw LumaImageModelError(message: "Luma AI only supports URL-based images. Please provide image URLs using `prompt.images` with publicly accessible URLs. Base64 and Uint8Array data are not supported.")
            }
            return url
        }
        func image(_ index: Int, weight: Double) -> JSONValue {
            .object(["url": .string(urls[index]), "weight": .number(imageConfigs.indices.contains(index) ? imageConfigs[index].weight ?? weight : weight)])
        }
        switch referenceType {
        case .image:
            if urls.count > 4 { throw LumaImageModelError(message: "Luma AI image supports up to 4 reference images. You provided \(urls.count) images.") }
            return ["image": .array(urls.indices.map { image($0, weight: 0.85) })]
        case .style:
            return ["style": .array(urls.indices.map { image($0, weight: 0.8) })]
        case .modifyImage:
            if urls.count > 1 { throw LumaImageModelError(message: "Luma AI modify_image only supports a single input image. You provided \(urls.count) images.") }
            return ["modify_image": image(0, weight: 1)]
        case .character:
            var identities: [String: [JSONValue]] = [:]
            for index in urls.indices {
                let id = imageConfigs.indices.contains(index) ? imageConfigs[index].id ?? "identity0" : "identity0"
                identities[id, default: []].append(.string(urls[index]))
            }
            for (id, images) in identities where images.count > 4 {
                throw LumaImageModelError(message: "Luma AI character supports up to 4 images per identity. Identity '\(id)' has \(images.count) images.")
            }
            return ["character": .object(identities.mapValues { .object(["images": .array($0)]) })]
        }
    }

    private func generationsURL(_ id: String? = nil) -> String {
        "\(config.baseURL)/dream-machine/v1/generations/\(id ?? "image")"
    }

    private func number(_ value: JSONValue?) -> Double? {
        if case .number(let value) = value { return value }
        return nil
    }
}

private struct LumaImageModelError: Error, LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/luma/src/luma-image-model.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

private let defaultPollIntervalMillis = 500
private let defaultMaxPollAttempts = 60000 / defaultPollIntervalMillis

struct LumaImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () -> [String: String?]
    let fetch: FetchFunction?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: @escaping @Sendable () -> [String: String?],
        fetch: FetchFunction?,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.currentDate = currentDate
    }
}

private struct LumaGenerationResponse: Codable, Sendable {
    enum State: String, Codable {
        case queued
        case dreaming
        case completed
        case failed
    }

    struct Assets: Codable, Sendable {
        let image: String?

        private enum CodingKeys: String, CodingKey {
            case image
        }
    }

    let id: String
    let state: State
    let failureReason: String?
    let assets: Assets?

    private enum CodingKeys: String, CodingKey {
        case id
        case state
        case failureReason = "failure_reason"
        case assets
    }
}

private let lumaGenerationResponseSchema = FlexibleSchema(
    Schema<LumaGenerationResponse>.codable(
        LumaGenerationResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct ParsedLumaProviderOptions {
    let requestOverrides: [String: JSONValue]
    let imageSettings: LumaImageSettings?
}

/// Luma image generation model.
/// Mirrors `LumaImageModel` from upstream TypeScript implementation.
public final class LumaImageModel: ImageModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }
    public let pollIntervalMillis: Int = defaultPollIntervalMillis
    public let maxPollAttempts: Int = defaultMaxPollAttempts

    private let modelIdentifier: LumaImageModelId
    private let config: LumaImageModelConfig

    init(modelId: LumaImageModelId, config: LumaImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        if options.seed != nil {
            warnings.append(.unsupportedSetting(
                setting: "seed",
                details: "This model does not support the `seed` option."
            ))
        }

        if options.size != nil {
            warnings.append(.unsupportedSetting(
                setting: "size",
                details: "This model does not support the `size` option. Use `aspectRatio` instead."
            ))
        }

        let parsedProviderOptions = parseProviderOptions(options.providerOptions)

        var body: [String: JSONValue] = [
            "model": .string(modelIdentifier.rawValue)
        ]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let aspectRatio = options.aspectRatio {
            body["aspect_ratio"] = .string(aspectRatio)
        }

        for (key, value) in parsedProviderOptions.requestOverrides {
            body[key] = value
        }

        let combinedHeaders = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        )
        let requestHeaders = combinedHeaders.compactMapValues { $0 }

        let generationResponse = try await postJsonToAPI(
            url: makeGenerationsURL(),
            headers: requestHeaders,
            body: JSONValue.object(body),
            failedResponseHandler: lumaFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: lumaGenerationResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let imageURL = try await pollForImageURL(
            generationId: generationResponse.value.id,
            headers: requestHeaders,
            abortSignal: options.abortSignal,
            imageSettings: parsedProviderOptions.imageSettings
        )

        let imageData = try await downloadImage(
            url: imageURL,
            abortSignal: options.abortSignal
        )

        return ImageModelV3GenerateResult(
            images: .binary([imageData]),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
                timestamp: config.currentDate(),
                modelId: modelIdentifier.rawValue,
                headers: generationResponse.responseHeaders
            )
        )
    }

    private func pollForImageURL(
        generationId: String,
        headers: [String: String],
        abortSignal: (@Sendable () -> Bool)?,
        imageSettings: LumaImageSettings?
    ) async throws -> String {
        let maxAttempts = imageSettings?.maxPollAttempts ?? maxPollAttempts
        let pollDelay = imageSettings?.pollIntervalMillis ?? pollIntervalMillis
        let url = makeGenerationsURL(generationId)

        for _ in 0..<maxAttempts {
            try checkAbort(abortSignal)

            let statusResponse = try await getFromAPI(
                url: url,
                headers: headers,
                failedResponseHandler: lumaFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: lumaGenerationResponseSchema),
                isAborted: abortSignal,
                fetch: config.fetch
            ).value

            switch statusResponse.state {
            case .completed:
                if let image = statusResponse.assets?.image {
                    return image
                }
                throw InvalidResponseDataError(
                    data: statusResponse,
                    message: "Image generation completed but no image was found."
                )
            case .failed:
                throw InvalidResponseDataError(
                    data: statusResponse,
                    message: "Image generation failed."
                )
            case .queued, .dreaming:
                try await delay(pollDelay)
            }
        }

        throw APICallError(
            message: "Image generation timed out after \(maxPollAttempts) attempts.",
            url: url,
            requestBodyValues: nil
        )
    }

    private func downloadImage(
        url: String,
        abortSignal: (@Sendable () -> Bool)?
    ) async throws -> Data {
        try await getFromAPI(
            url: url,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: abortSignal,
            fetch: config.fetch
        ).value
    }

    private func makeGenerationsURL(_ generationId: String? = nil) -> String {
        "\(config.baseURL)/dream-machine/v1/generations/\(generationId ?? "image")"
    }

    private func parseProviderOptions(_ providerOptions: SharedV3ProviderOptions?) -> ParsedLumaProviderOptions {
        guard let options = providerOptions?["luma"] else {
            return ParsedLumaProviderOptions(requestOverrides: [:], imageSettings: nil)
        }

        var overrides: [String: JSONValue] = [:]
        var pollInterval: Int?
        var maxAttempts: Int?

        for (key, value) in options {
            switch key {
            case "pollIntervalMillis":
                pollInterval = intValue(from: value) ?? pollInterval
            case "maxPollAttempts":
                maxAttempts = intValue(from: value) ?? maxAttempts
            default:
                overrides[key] = value
            }
        }

        let settings: LumaImageSettings?
        if pollInterval != nil || maxAttempts != nil {
            settings = LumaImageSettings(
                pollIntervalMillis: pollInterval,
                maxPollAttempts: maxAttempts
            )
        } else {
            settings = nil
        }

        return ParsedLumaProviderOptions(
            requestOverrides: overrides,
            imageSettings: settings
        )
    }

    private func intValue(from value: JSONValue) -> Int? {
        switch value {
        case .number(let number):
            return Int(number)
        case .string(let string):
            return Int(string)
        default:
            return nil
        }
    }

    private func checkAbort(_ abortSignal: (@Sendable () -> Bool)?) throws {
        if abortSignal?() == true {
            throw CancellationError()
        }
        try Task.checkCancellation()
    }
}

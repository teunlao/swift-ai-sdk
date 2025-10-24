import Foundation
import AISDKProvider
import AISDKProviderUtils

// MARK: - Config

struct ReplicateImageModelConfig: Sendable {
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

// MARK: - Response Schema

private struct ReplicateImageResponse: Codable, Sendable {
    enum Output: Sendable {
        case array([String])
        case string(String)
    }

    let output: Output
}

// Custom Codable for union string | string[]
extension ReplicateImageResponse.Output: Codable {
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let arr = try? container.decode([String].self) {
            self = .array(arr)
        } else if let str = try? container.decode(String.self) {
            self = .string(str)
        } else {
            throw DecodingError.typeMismatch(
                ReplicateImageResponse.Output.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Expected string or array of strings")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .array(let arr):
            try container.encode(arr)
        case .string(let str):
            try container.encode(str)
        }
    }
}

private let replicateImageResponseSchema = FlexibleSchema(
    Schema<ReplicateImageResponse>.codable(
        ReplicateImageResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

// MARK: - Image Model

/// Replicate image generation model.
/// Mirrors `packages/replicate/src/replicate-image-model.ts`.
public final class ReplicateImageModel: ImageModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: ReplicateImageModelId
    private let config: ReplicateImageModelConfig

    init(_ modelId: ReplicateImageModelId, config: ReplicateImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        var warnings: [ImageModelV3CallWarning] = []

        // Build headers: provider + request + prefer: wait
        var defaultHeaders = config.headers()
        defaultHeaders["prefer"] = "wait"
        let merged = combineHeaders(defaultHeaders, options.headers?.mapValues { Optional($0) })
        let headers = merged.compactMapValues { $0 }

        // Split model/version if provided as "model:version"
        let parts = modelIdentifier.rawValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: true)
        let modelPart = String(parts.first ?? Substring(modelIdentifier.rawValue))
        let versionPart: String? = parts.count == 2 ? String(parts[1]) : nil

        // Prepare body
        var input: [String: JSONValue] = [
            "prompt": .string(options.prompt),
            "num_outputs": .number(Double(options.n))
        ]

        if let aspect = options.aspectRatio { input["aspect_ratio"] = .string(aspect) }
        if let size = options.size { input["size"] = .string(size) }
        if let seed = options.seed { input["seed"] = .number(Double(seed)) }

        if let replicateOptions = options.providerOptions?["replicate"] {
            // Merge providerOptions.replicate into input (Object.assign semantics)
            for (k, v) in replicateOptions { input[k] = v }
        }

        var requestBody: [String: JSONValue] = ["input": .object(input)]
        let url: String
        if let version = versionPart {
            url = "\(config.baseURL)/predictions"
            requestBody["version"] = .string(version)
        } else {
            url = "\(config.baseURL)/models/\(modelPart)/predictions"
        }

        // POST to create prediction
        let postResponse = try await postJsonToAPI(
            url: url,
            headers: headers,
            body: JSONValue.object(requestBody),
            failedResponseHandler: replicateFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: replicateImageResponseSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        // Extract output URLs
        let outputURLs: [String] = {
            switch postResponse.value.output {
            case .array(let arr): return arr
            case .string(let s): return [s]
            }
        }()

        // Download each image URL as binary
        var imagesData: [Data] = []
        imagesData.reserveCapacity(outputURLs.count)

        for url in outputURLs {
            let result = try await getFromAPI(
                url: url,
                headers: nil,
                failedResponseHandler: replicateFailedResponseHandler,
                successfulResponseHandler: createBinaryResponseHandler(),
                isAborted: options.abortSignal,
                fetch: config.fetch
            )
            imagesData.append(result.value)
        }

        return ImageModelV3GenerateResult(
            images: .binary(imagesData),
            warnings: warnings,
            providerMetadata: nil,
            response: ImageModelV3ResponseInfo(
                timestamp: config.currentDate(),
                modelId: modelIdentifier.rawValue,
                headers: postResponse.responseHeaders
            )
        )
    }
}

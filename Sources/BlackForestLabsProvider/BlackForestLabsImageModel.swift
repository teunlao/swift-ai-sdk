import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/black-forest-labs/src/black-forest-labs-image-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

private let defaultPollIntervalMillis = 500
private let defaultPollTimeoutMillis = 60_000

struct BlackForestLabsImageModelConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: (@Sendable () -> [String: String?])?
    let fetch: FetchFunction?
    let pollIntervalMillis: Int?
    let pollTimeoutMillis: Int?
    let currentDate: @Sendable () -> Date

    init(
        provider: String,
        baseURL: String,
        headers: (@Sendable () -> [String: String?])? = nil,
        fetch: FetchFunction? = nil,
        pollIntervalMillis: Int? = nil,
        pollTimeoutMillis: Int? = nil,
        currentDate: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.provider = provider
        self.baseURL = baseURL
        self.headers = headers
        self.fetch = fetch
        self.pollIntervalMillis = pollIntervalMillis
        self.pollTimeoutMillis = pollTimeoutMillis
        self.currentDate = currentDate
    }
}

public struct BlackForestLabsImageProviderOptions: Sendable, Equatable {
    public var imagePrompt: String?
    public var imagePromptStrength: Double?
    public var steps: Int?
    public var guidance: Double?
    public var width: Int?
    public var height: Int?
    public var outputFormat: BlackForestLabsOutputFormat?
    public var promptUpsampling: Bool?
    public var raw: Bool?
    public var safetyTolerance: Int?
    public var webhookSecret: String?
    public var webhookUrl: String?
    public var pollIntervalMillis: Int?
    public var pollTimeoutMillis: Int?

    public init(
        imagePrompt: String? = nil,
        imagePromptStrength: Double? = nil,
        steps: Int? = nil,
        guidance: Double? = nil,
        width: Int? = nil,
        height: Int? = nil,
        outputFormat: BlackForestLabsOutputFormat? = nil,
        promptUpsampling: Bool? = nil,
        raw: Bool? = nil,
        safetyTolerance: Int? = nil,
        webhookSecret: String? = nil,
        webhookUrl: String? = nil,
        pollIntervalMillis: Int? = nil,
        pollTimeoutMillis: Int? = nil
    ) {
        self.imagePrompt = imagePrompt
        self.imagePromptStrength = imagePromptStrength
        self.steps = steps
        self.guidance = guidance
        self.width = width
        self.height = height
        self.outputFormat = outputFormat
        self.promptUpsampling = promptUpsampling
        self.raw = raw
        self.safetyTolerance = safetyTolerance
        self.webhookSecret = webhookSecret
        self.webhookUrl = webhookUrl
        self.pollIntervalMillis = pollIntervalMillis
        self.pollTimeoutMillis = pollTimeoutMillis
    }
}

private let optionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
])

public let blackForestLabsImageProviderOptionsSchema = FlexibleSchema(
    Schema<BlackForestLabsImageProviderOptions>(
        jsonSchemaResolver: { optionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func readString(_ key: String) -> String? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .string(let str) = raw else { return nil }
                    return str
                }

                func readBool(_ key: String) -> Bool? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .bool(let b) = raw else { return nil }
                    return b
                }

                func readNumber(_ key: String) -> Double? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .number(let n) = raw else { return nil }
                    return n
                }

                func readInt(_ key: String) -> Int? {
                    guard let n = readNumber(key) else { return nil }
                    let i = Int(n)
                    guard Double(i) == n else { return nil }
                    return i
                }

                var options = BlackForestLabsImageProviderOptions()

                options.imagePrompt = readString("imagePrompt")
                options.imagePromptStrength = readNumber("imagePromptStrength")
                options.steps = readInt("steps")
                options.guidance = readNumber("guidance")
                options.width = readInt("width")
                options.height = readInt("height")

                if let rawOutput = readString("outputFormat") {
                    options.outputFormat = BlackForestLabsOutputFormat(rawValue: rawOutput)
                }

                options.promptUpsampling = readBool("promptUpsampling")
                options.raw = readBool("raw")
                options.safetyTolerance = readInt("safetyTolerance")
                options.webhookSecret = readString("webhookSecret")

                if let urlString = readString("webhookUrl") {
                    if let url = URL(string: urlString), url.scheme != nil, url.host != nil {
                        options.webhookUrl = urlString
                    }
                }

                options.pollIntervalMillis = readInt("pollIntervalMillis")
                options.pollTimeoutMillis = readInt("pollTimeoutMillis")

                // Value-range validation (mirrors zod constraints; unknown keys are ignored/stripped).
                if let strength = options.imagePromptStrength, !(0.0...1.0).contains(strength) {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "imagePromptStrength must be between 0 and 1"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let steps = options.steps, steps <= 0 {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "steps must be a positive integer"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let guidance = options.guidance, guidance < 0 {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "guidance must be >= 0"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let width = options.width, !(256...1920).contains(width) {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "width must be between 256 and 1920"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let height = options.height, !(256...1920).contains(height) {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "height must be between 256 and 1920"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let tolerance = options.safetyTolerance, !(0...6).contains(tolerance) {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "safetyTolerance must be between 0 and 6"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let pollInterval = options.pollIntervalMillis, pollInterval <= 0 {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "pollIntervalMillis must be a positive integer"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let pollTimeout = options.pollTimeoutMillis, pollTimeout <= 0 {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "pollTimeoutMillis must be a positive integer"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct BFLSubmitResponse: Codable, Sendable {
    let id: String
    let pollingURL: String
    let cost: Double?
    let inputMP: Double?
    let outputMP: Double?

    private enum CodingKeys: String, CodingKey {
        case id
        case pollingURL = "polling_url"
        case cost
        case inputMP = "input_mp"
        case outputMP = "output_mp"
    }
}

private let bflSubmitSchema = FlexibleSchema(
    Schema.codable(
        BFLSubmitResponse.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private struct BFLPollResponse: Sendable {
    struct Result: Sendable {
        let sample: String
        let seed: Double?
        let startTime: Double?
        let endTime: Double?
        let duration: Double?
    }

    let status: String
    let result: Result?
}

private let bflPollSchema = FlexibleSchema(
    Schema<BFLPollResponse>(
        jsonSchemaResolver: { .object(["type": .string("object")]) },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "poll response must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let statusValue = dict["status"] ?? dict["state"]
                guard let rawStatus = statusValue, rawStatus != .null, case .string(let status) = rawStatus else {
                    let error = SchemaValidationIssuesError(
                        vendor: "blackForestLabs",
                        issues: "Missing status in Black Forest Labs poll response"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var result: BFLPollResponse.Result?
                if let rawResult = dict["result"], rawResult != .null {
                    guard case .object(let resultObj) = rawResult else {
                        let error = SchemaValidationIssuesError(
                            vendor: "blackForestLabs",
                            issues: "result must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawResult, cause: error))
                    }

                    guard let sampleRaw = resultObj["sample"], sampleRaw != .null, case .string(let sample) = sampleRaw else {
                        // Keep result as nil if sample is missing; caller handles Ready+missing sample.
                        return .success(value: BFLPollResponse(status: status, result: nil))
                    }

                    let seed: Double?
                    if let rawSeed = resultObj["seed"], rawSeed != .null, case .number(let n) = rawSeed { seed = n } else { seed = nil }

                    let startTime: Double?
                    if let rawStart = resultObj["start_time"], rawStart != .null, case .number(let n) = rawStart { startTime = n } else { startTime = nil }

                    let endTime: Double?
                    if let rawEnd = resultObj["end_time"], rawEnd != .null, case .number(let n) = rawEnd { endTime = n } else { endTime = nil }

                    let duration: Double?
                    if let rawDuration = resultObj["duration"], rawDuration != .null, case .number(let n) = rawDuration { duration = n } else { duration = nil }

                    result = BFLPollResponse.Result(
                        sample: sample,
                        seed: seed,
                        startTime: startTime,
                        endTime: endTime,
                        duration: duration
                    )
                }

                return .success(value: BFLPollResponse(status: status, result: result))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private struct BFLErrorPayload: Codable, Sendable {
    let message: String?
    let detail: JSONValue?
}

private let bflErrorSchema = FlexibleSchema(
    Schema.codable(
        BFLErrorPayload.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private func bflErrorToMessage(_ error: BFLErrorPayload) -> String? {
    if let detail = error.detail, detail != .null {
        if case .string(let str) = detail {
            return str
        }
        return (try? jsonStringify(detail)) ?? nil
    }
    return error.message
}

private func jsonStringify(_ value: JSONValue) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw EncodingError.invalidValue(
            value,
            EncodingError.Context(codingPath: [], debugDescription: "Failed to encode JSON string")
        )
    }
    return string
}

private let bflFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: bflErrorSchema,
    errorToMessage: { payload in
        bflErrorToMessage(payload) ?? "Unknown Black Forest Labs error"
    }
)

public final class BlackForestLabsImageModel: ImageModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: BlackForestLabsImageModelId
    private let config: BlackForestLabsImageModelConfig

    init(modelId: BlackForestLabsImageModelId, config: BlackForestLabsImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        let (body, warnings) = try await getArgs(options)

        let bflOptions = try await parseProviderOptions(
            provider: "blackForestLabs",
            providerOptions: options.providerOptions,
            schema: blackForestLabsImageProviderOptionsSchema
        )

        let currentDate = config.currentDate()
        let combinedHeaders = combineHeaders(
            config.headers?() ?? [:],
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }

        let submit = try await postJsonToAPI(
            url: "\(config.baseURL)/\(modelIdentifier.rawValue)",
            headers: combinedHeaders,
            body: JSONValue.object(body),
            failedResponseHandler: bflFailedResponseHandler,
            successfulResponseHandler: createJsonResponseHandler(responseSchema: bflSubmitSchema),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let pollUrl = submit.value.pollingURL
        let requestId = submit.value.id

        let poll = try await pollForImageUrl(
            pollUrl: pollUrl,
            requestId: requestId,
            headers: combinedHeaders,
            abortSignal: options.abortSignal,
            pollOverrides: (
                pollIntervalMillis: bflOptions?.pollIntervalMillis,
                pollTimeoutMillis: bflOptions?.pollTimeoutMillis
            )
        )

        let imageResponse = try await getFromAPI(
            url: poll.imageUrl,
            headers: combinedHeaders,
            failedResponseHandler: createStatusCodeErrorResponseHandler(),
            successfulResponseHandler: createBinaryResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        var imageMetadata: [String: JSONValue] = [:]

        if let seed = poll.seed {
            imageMetadata["seed"] = .number(seed)
        }
        if let startTime = poll.startTime {
            imageMetadata["start_time"] = .number(startTime)
        }
        if let endTime = poll.endTime {
            imageMetadata["end_time"] = .number(endTime)
        }
        if let duration = poll.duration {
            imageMetadata["duration"] = .number(duration)
        }
        if let cost = submit.value.cost {
            imageMetadata["cost"] = .number(cost)
        }
        if let inputMP = submit.value.inputMP {
            imageMetadata["inputMegapixels"] = .number(inputMP)
        }
        if let outputMP = submit.value.outputMP {
            imageMetadata["outputMegapixels"] = .number(outputMP)
        }

        let providerMetadata: ImageModelV3ProviderMetadata = [
            "blackForestLabs": ImageModelV3ProviderMetadataValue(
                images: [.object(imageMetadata)]
            )
        ]

        return ImageModelV3GenerateResult(
            images: .binary([imageResponse.value]),
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: ImageModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: imageResponse.responseHeaders
            )
        )
    }

    private func getArgs(_ options: ImageModelV3CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV3Warning]) {
        var warnings: [SharedV3Warning] = []

        let finalAspectRatio: String? = {
            if let aspectRatio = options.aspectRatio {
                return aspectRatio
            }
            if let size = options.size {
                return convertSizeToAspectRatio(size)
            }
            return nil
        }()

        if options.size != nil, options.aspectRatio == nil {
            warnings.append(
                .unsupported(
                    feature: "size",
                    details: "Deriving aspect_ratio from size. Use the width and height provider options to specify dimensions for models that support them."
                )
            )
        } else if options.size != nil, options.aspectRatio != nil {
            warnings.append(
                .unsupported(
                    feature: "size",
                    details: "Black Forest Labs ignores size when aspectRatio is provided. Use the width and height provider options to specify dimensions for models that support them"
                )
            )
        }

        let bflOptions = try await parseProviderOptions(
            provider: "blackForestLabs",
            providerOptions: options.providerOptions,
            schema: blackForestLabsImageProviderOptionsSchema
        )

        let sizeComponents: (width: Int, height: Int)? = {
            guard let size = options.size else { return nil }
            let parts = size.split(separator: "x", maxSplits: 1).map(String.init)
            guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]) else { return nil }
            return (w, h)
        }()

        let inputImages: [String] = (options.files ?? []).map { file in
            switch file {
            case .url(let url, _):
                return url
            case let .file(_, data, _):
                switch data {
                case .base64(let str):
                    return str
                case .binary(let bytes):
                    return bytes.base64EncodedString()
                }
            }
        }

        if inputImages.count > 10 {
            throw InvalidArgumentError(argument: "files", message: "Black Forest Labs supports up to 10 input images.")
        }

        var inputImagesObj: [String: JSONValue] = [:]
        for (index, img) in inputImages.enumerated() {
            let key = index == 0 ? "input_image" : "input_image_\(index + 1)"
            inputImagesObj[key] = .string(img)
        }

        var maskValue: String?
        if let mask = options.mask {
            switch mask {
            case .url(let url, _):
                maskValue = url
            case let .file(_, data, _):
                switch data {
                case .base64(let str):
                    maskValue = str
                case .binary(let bytes):
                    maskValue = bytes.base64EncodedString()
                }
            }
        }

        var body: [String: JSONValue] = [:]

        if let prompt = options.prompt {
            body["prompt"] = .string(prompt)
        }

        if let seed = options.seed {
            body["seed"] = .number(Double(seed))
        }

        if let finalAspectRatio {
            body["aspect_ratio"] = .string(finalAspectRatio)
        }

        if let width = bflOptions?.width ?? sizeComponents?.width {
            body["width"] = .number(Double(width))
        }

        if let height = bflOptions?.height ?? sizeComponents?.height {
            body["height"] = .number(Double(height))
        }

        if let steps = bflOptions?.steps {
            body["steps"] = .number(Double(steps))
        }

        if let guidance = bflOptions?.guidance {
            body["guidance"] = .number(guidance)
        }

        if let strength = bflOptions?.imagePromptStrength {
            body["image_prompt_strength"] = .number(strength)
        }

        if let imagePrompt = bflOptions?.imagePrompt {
            body["image_prompt"] = .string(imagePrompt)
        }

        for (key, value) in inputImagesObj {
            body[key] = value
        }

        if let maskValue {
            body["mask"] = .string(maskValue)
        }

        if let outputFormat = bflOptions?.outputFormat {
            body["output_format"] = .string(outputFormat.rawValue)
        }

        if let promptUpsampling = bflOptions?.promptUpsampling {
            body["prompt_upsampling"] = .bool(promptUpsampling)
        }

        if let raw = bflOptions?.raw {
            body["raw"] = .bool(raw)
        }

        if let tolerance = bflOptions?.safetyTolerance {
            body["safety_tolerance"] = .number(Double(tolerance))
        }

        if let webhookSecret = bflOptions?.webhookSecret {
            body["webhook_secret"] = .string(webhookSecret)
        }

        if let webhookUrl = bflOptions?.webhookUrl {
            body["webhook_url"] = .string(webhookUrl)
        }

        return (body: body, warnings: warnings)
    }

    private func pollForImageUrl(
        pollUrl: String,
        requestId: String,
        headers: [String: String],
        abortSignal: (@Sendable () -> Bool)?,
        pollOverrides: (pollIntervalMillis: Int?, pollTimeoutMillis: Int?)? = nil
    ) async throws -> (imageUrl: String, seed: Double?, startTime: Double?, endTime: Double?, duration: Double?) {
        let pollIntervalMillis = pollOverrides?.pollIntervalMillis ?? config.pollIntervalMillis ?? defaultPollIntervalMillis
        let pollTimeoutMillis = pollOverrides?.pollTimeoutMillis ?? config.pollTimeoutMillis ?? defaultPollTimeoutMillis
        let maxPollAttempts = Int(ceil(Double(pollTimeoutMillis) / Double(max(1, pollIntervalMillis))))

        var urlComponents = URLComponents(string: pollUrl)
        if urlComponents?.queryItems?.contains(where: { $0.name == "id" }) != true {
            var queryItems = urlComponents?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "id", value: requestId))
            urlComponents?.queryItems = queryItems
        }

        let urlString = urlComponents?.url?.absoluteString ?? pollUrl

        for _ in 0..<maxPollAttempts {
            if abortSignal?() == true {
                throw CancellationError()
            }

            let response = try await getFromAPI(
                url: urlString,
                headers: headers,
                failedResponseHandler: bflFailedResponseHandler,
                successfulResponseHandler: createJsonResponseHandler(responseSchema: bflPollSchema),
                isAborted: abortSignal,
                fetch: config.fetch
            )

            let status = response.value.status
            if status == "Ready" {
                if let sample = response.value.result?.sample {
                    return (
                        imageUrl: sample,
                        seed: response.value.result?.seed,
                        startTime: response.value.result?.startTime,
                        endTime: response.value.result?.endTime,
                        duration: response.value.result?.duration
                    )
                }
                throw InvalidResponseDataError(
                    data: response.rawValue as Any,
                    message: "Black Forest Labs poll response is Ready but missing result.sample"
                )
            }

            if status == "Error" || status == "Failed" {
                throw InvalidResponseDataError(
                    data: response.rawValue as Any,
                    message: "Black Forest Labs generation failed."
                )
            }

            try await delay(pollIntervalMillis)
        }

        throw InvalidResponseDataError(data: pollUrl, message: "Black Forest Labs generation timed out.")
    }
}

private func convertSizeToAspectRatio(_ size: String) -> String? {
    let parts = size.split(separator: "x", maxSplits: 1).map(String.init)
    guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else { return nil }
    guard width > 0, height > 0 else { return nil }
    let g = gcd(width, height)
    return "\(width / g):\(height / g)"
}

private func gcd(_ a: Int, _ b: Int) -> Int {
    var x = abs(a)
    var y = abs(b)
    while y != 0 {
        let t = y
        y = x % y
        x = t
    }
    return x
}

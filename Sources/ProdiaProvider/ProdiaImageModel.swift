import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/prodia/src/prodia-image-model.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

struct ProdiaImageModelConfig: Sendable {
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

public struct ProdiaImageProviderOptions: Sendable, Equatable {
    public var steps: Int?
    public var width: Int?
    public var height: Int?
    public var stylePreset: String?
    public var loras: [String]?
    public var progressive: Bool?

    public init(
        steps: Int? = nil,
        width: Int? = nil,
        height: Int? = nil,
        stylePreset: String? = nil,
        loras: [String]? = nil,
        progressive: Bool? = nil
    ) {
        self.steps = steps
        self.width = width
        self.height = height
        self.stylePreset = stylePreset
        self.loras = loras
        self.progressive = progressive
    }
}

private let stylePresets: Set<String> = [
    "3d-model",
    "analog-film",
    "anime",
    "cinematic",
    "comic-book",
    "digital-art",
    "enhance",
    "fantasy-art",
    "isometric",
    "line-art",
    "low-poly",
    "neon-punk",
    "origami",
    "photographic",
    "pixel-art",
    "texture",
    "craft-clay",
]

private let optionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
])

private let prodiaImageProviderOptionsSchema = FlexibleSchema(
    Schema<ProdiaImageProviderOptions>(
        jsonSchemaResolver: { optionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "prodia",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func readString(_ key: String) -> String? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .string(let s) = raw else { return nil }
                    return s
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

                func readStringArray(_ key: String) -> [String]? {
                    guard let raw = dict[key], raw != .null else { return nil }
                    guard case .array(let arr) = raw else { return nil }
                    var out: [String] = []
                    out.reserveCapacity(arr.count)
                    for item in arr {
                        guard case .string(let s) = item else { return nil }
                        out.append(s)
                    }
                    return out
                }

                var options = ProdiaImageProviderOptions()
                options.steps = readInt("steps")
                options.width = readInt("width")
                options.height = readInt("height")
                options.stylePreset = readString("stylePreset")
                options.loras = readStringArray("loras")
                options.progressive = readBool("progressive")

                if let steps = options.steps, !(1...4).contains(steps) {
                    let error = SchemaValidationIssuesError(
                        vendor: "prodia",
                        issues: "steps must be between 1 and 4"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let width = options.width, !(256...1920).contains(width) {
                    let error = SchemaValidationIssuesError(
                        vendor: "prodia",
                        issues: "width must be between 256 and 1920"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let height = options.height, !(256...1920).contains(height) {
                    let error = SchemaValidationIssuesError(
                        vendor: "prodia",
                        issues: "height must be between 256 and 1920"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let style = options.stylePreset, !stylePresets.contains(style) {
                    let error = SchemaValidationIssuesError(
                        vendor: "prodia",
                        issues: "stylePreset must be one of the supported presets"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                if let loras = options.loras, loras.count > 3 {
                    let error = SchemaValidationIssuesError(
                        vendor: "prodia",
                        issues: "loras must have at most 3 items"
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

private struct ProdiaJobResult: Codable, Sendable {
    struct Config: Codable, Sendable {
        let seed: Double?
    }

    struct Metrics: Codable, Sendable {
        let elapsed: Double?
        let ips: Double?
    }

    let id: String
    let createdAt: String?
    let updatedAt: String?
    let config: Config?
    let metrics: Metrics?

    enum CodingKeys: String, CodingKey {
        case id
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case config
        case metrics
    }
}

private struct ProdiaErrorPayload: Codable, Sendable {
    let message: String?
    let detail: JSONValue?
    let error: String?
}

private let prodiaErrorSchema = FlexibleSchema(
    Schema.codable(
        ProdiaErrorPayload.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private func prodiaErrorToMessage(_ payload: ProdiaErrorPayload) -> String {
    if let detail = payload.detail, detail != .null {
        if case .string(let s) = detail {
            return s
        }
        if let data = try? JSONEncoder().encode(detail),
           let str = String(data: data, encoding: .utf8) {
            return str
        }
    }
    return payload.error ?? payload.message ?? "Unknown Prodia error"
}

private let prodiaFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: prodiaErrorSchema,
    errorToMessage: { payload in
        prodiaErrorToMessage(payload)
    }
)

private struct MultipartPart: Sendable {
    let headers: [String: String]
    let body: Data
}

private struct MultipartResult: Sendable {
    let jobResult: ProdiaJobResult
    let imageBytes: Data
}

private func extractBoundary(from contentType: String) -> String? {
    guard let range = contentType.range(of: "boundary=") else { return nil }
    let tail = contentType[range.upperBound...]
    if let token = tail.split(whereSeparator: { $0 == ";" || $0 == " " || $0 == "\t" }).first {
        return String(token)
    }
    return nil
}

private func parseMultipart(_ data: Data, boundary: String) -> [MultipartPart] {
    let bytes = [UInt8](data)
    let boundaryBytes = Array("--\(boundary)".utf8)
    let endBoundaryBytes = Array("--\(boundary)--".utf8)

    guard !boundaryBytes.isEmpty, bytes.count >= boundaryBytes.count else { return [] }

    var positions: [Int] = []
    positions.reserveCapacity(8)

    var i = 0
    while i <= bytes.count - boundaryBytes.count {
        var match = true
        for j in 0..<boundaryBytes.count {
            if bytes[i + j] != boundaryBytes[j] {
                match = false
                break
            }
        }
        if match {
            positions.append(i)
            i += boundaryBytes.count
        } else {
            i += 1
        }
    }

    guard positions.count >= 2 else { return [] }

    var parts: [MultipartPart] = []
    parts.reserveCapacity(max(0, positions.count - 1))

    for index in 0..<(positions.count - 1) {
        let boundaryPos = positions[index]
        let start = boundaryPos + boundaryBytes.count
        let end = positions[index + 1]

        // Skip end boundary marker.
        if boundaryPos + endBoundaryBytes.count <= bytes.count {
            var isEndBoundary = true
            for j in 0..<endBoundaryBytes.count where isEndBoundary {
                if bytes[boundaryPos + j] != endBoundaryBytes[j] {
                    isEndBoundary = false
                }
            }
            if isEndBoundary {
                continue
            }
        }

        var partStart = start
        if partStart + 1 < end, bytes[partStart] == 0x0d, bytes[partStart + 1] == 0x0a {
            partStart += 2
        } else if partStart < end, bytes[partStart] == 0x0a {
            partStart += 1
        }

        var partEnd = end
        if partEnd - 2 >= partStart, bytes[partEnd - 2] == 0x0d, bytes[partEnd - 1] == 0x0a {
            partEnd -= 2
        } else if partEnd - 1 >= partStart, bytes[partEnd - 1] == 0x0a {
            partEnd -= 1
        }

        if partStart >= partEnd { continue }

        let partData = Array(bytes[partStart..<partEnd])

        var headerEnd: Int? = nil
        if partData.count >= 4 {
            for j in 0..<(partData.count - 3) {
                if partData[j] == 0x0d,
                   partData[j + 1] == 0x0a,
                   partData[j + 2] == 0x0d,
                   partData[j + 3] == 0x0a {
                    headerEnd = j
                    break
                }
                if partData[j] == 0x0a, partData[j + 1] == 0x0a {
                    headerEnd = j
                    break
                }
            }
        }

        guard let headerEnd else { continue }

        let headerBytes = Data(partData[0..<headerEnd])
        let headerString = String(data: headerBytes, encoding: .utf8) ?? ""

        var headers: [String: String] = [:]
        for rawLine in headerString.split(whereSeparator: { $0 == "\n" || $0 == "\r" }) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty {
                headers[key] = value
            }
        }

        var bodyStart = headerEnd + 2
        if headerEnd < partData.count, partData[headerEnd] == 0x0d {
            bodyStart = headerEnd + 4
        }
        if bodyStart > partData.count { continue }

        let body = Data(partData[bodyStart..<partData.count])
        parts.append(MultipartPart(headers: headers, body: body))
    }

    return parts
}

private func createMultipartResponseHandler() -> ResponseHandler<MultipartResult> {
    { input in
        let response = input.response
        let headers = extractResponseHeaders(from: response.httpResponse)
        let contentType = response.httpResponse.value(forHTTPHeaderField: "Content-Type") ?? ""

        guard let boundary = extractBoundary(from: contentType) else {
            throw InvalidResponseDataError(
                data: ["contentType": contentType],
                message: "Prodia response missing multipart boundary in content-type: \(contentType)"
            )
        }

        let data = try await response.body.collectData()
        let parts = parseMultipart(data, boundary: boundary)

        var jobResult: ProdiaJobResult?
        var imageBytes: Data?

        for part in parts {
            let contentDisposition = part.headers["content-disposition"] ?? ""
            let partContentType = part.headers["content-type"] ?? ""

            if contentDisposition.contains("name=\"job\"") {
                jobResult = try JSONDecoder().decode(ProdiaJobResult.self, from: part.body)
            } else if contentDisposition.contains("name=\"output\"") {
                imageBytes = part.body
            } else if partContentType.lowercased().hasPrefix("image/") {
                imageBytes = part.body
            }
        }

        guard let jobResult else {
            throw InvalidResponseDataError(
                data: nil,
                message: "Prodia multipart response missing job part"
            )
        }

        guard let imageBytes else {
            throw InvalidResponseDataError(
                data: nil,
                message: "Prodia multipart response missing output image"
            )
        }

        return ResponseHandlerResult(
            value: MultipartResult(jobResult: jobResult, imageBytes: imageBytes),
            responseHeaders: headers
        )
    }
}

public final class ProdiaImageModel: ImageModelV3 {
    public var provider: String { config.provider }
    public var modelId: String { modelIdentifier.rawValue }
    public var maxImagesPerCall: ImageModelV3MaxImagesPerCall { .value(1) }

    private let modelIdentifier: ProdiaImageModelId
    private let config: ProdiaImageModelConfig

    init(modelId: ProdiaImageModelId, config: ProdiaImageModelConfig) {
        self.modelIdentifier = modelId
        self.config = config
    }

    public func doGenerate(options: ImageModelV3CallOptions) async throws -> ImageModelV3GenerateResult {
        let (body, warnings) = try await getArgs(options)

        let currentDate = config.currentDate()
        var combinedHeaders = combineHeaders(
            config.headers(),
            options.headers?.mapValues { Optional($0) }
        ).compactMapValues { $0 }
        combinedHeaders["Accept"] = "multipart/form-data; image/png"

        let multipart = try await postJsonToAPI(
            url: "\(config.baseURL)/job",
            headers: combinedHeaders,
            body: JSONValue.object(body),
            failedResponseHandler: prodiaFailedResponseHandler,
            successfulResponseHandler: createMultipartResponseHandler(),
            isAborted: options.abortSignal,
            fetch: config.fetch
        )

        let jobResult = multipart.value.jobResult
        let imageData = multipart.value.imageBytes

        var imageMetadata: [String: JSONValue] = [
            "jobId": .string(jobResult.id)
        ]
        if let seed = jobResult.config?.seed {
            imageMetadata["seed"] = .number(seed)
        }
        if let elapsed = jobResult.metrics?.elapsed {
            imageMetadata["elapsed"] = .number(elapsed)
        }
        if let ips = jobResult.metrics?.ips {
            imageMetadata["iterationsPerSecond"] = .number(ips)
        }
        if let createdAt = jobResult.createdAt {
            imageMetadata["createdAt"] = .string(createdAt)
        }
        if let updatedAt = jobResult.updatedAt {
            imageMetadata["updatedAt"] = .string(updatedAt)
        }

        let providerMetadata: ImageModelV3ProviderMetadata = [
            "prodia": ImageModelV3ProviderMetadataValue(images: [.object(imageMetadata)])
        ]

        return ImageModelV3GenerateResult(
            images: .binary([imageData]),
            warnings: warnings,
            providerMetadata: providerMetadata,
            response: ImageModelV3ResponseInfo(
                timestamp: currentDate,
                modelId: modelIdentifier.rawValue,
                headers: multipart.responseHeaders
            )
        )
    }

    private func getArgs(_ options: ImageModelV3CallOptions) async throws -> (body: [String: JSONValue], warnings: [SharedV3Warning]) {
        var warnings: [SharedV3Warning] = []

        let prodiaOptions = try await parseProviderOptions(
            provider: "prodia",
            providerOptions: options.providerOptions,
            schema: prodiaImageProviderOptionsSchema
        )

        var widthFromSize: Double?
        var heightFromSize: Double?
        if let size = options.size {
            let parts = size.split(separator: "x", omittingEmptySubsequences: false)
            if parts.count == 2,
               let width = Double(parts[0]),
               let height = Double(parts[1]),
               width.isFinite,
               height.isFinite,
               !parts[0].isEmpty,
               !parts[1].isEmpty {
                widthFromSize = width
                heightFromSize = height
            } else {
                warnings.append(
                    .unsupported(
                        feature: "size",
                        details: "Invalid size format: \(size). Expected format: WIDTHxHEIGHT (e.g., 1024x1024)"
                    )
                )
            }
        }

        var jobConfig: [String: JSONValue] = [:]

        if let prompt = options.prompt {
            jobConfig["prompt"] = .string(prompt)
        }

        if let width = prodiaOptions?.width {
            jobConfig["width"] = .number(Double(width))
        } else if let widthFromSize {
            jobConfig["width"] = .number(widthFromSize)
        }

        if let height = prodiaOptions?.height {
            jobConfig["height"] = .number(Double(height))
        } else if let heightFromSize {
            jobConfig["height"] = .number(heightFromSize)
        }

        if let seed = options.seed {
            jobConfig["seed"] = .number(Double(seed))
        }

        if let steps = prodiaOptions?.steps {
            jobConfig["steps"] = .number(Double(steps))
        }

        if let style = prodiaOptions?.stylePreset {
            jobConfig["style_preset"] = .string(style)
        }

        if let loras = prodiaOptions?.loras, !loras.isEmpty {
            jobConfig["loras"] = .array(loras.map { .string($0) })
        }

        if let progressive = prodiaOptions?.progressive {
            jobConfig["progressive"] = .bool(progressive)
        }

        let body: [String: JSONValue] = [
            "type": .string(modelIdentifier.rawValue),
            "config": .object(jobConfig),
        ]

        return (body: body, warnings: warnings)
    }
}


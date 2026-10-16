import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct XAIImageModelOptions: Codable, Sendable, Equatable {
    public var aspectRatio: String?
    public var outputFormat: String?
    public var syncMode: Bool?
    public var resolution: String?
    public var quality: String?
    public var user: String?

    public init(aspectRatio: String? = nil, outputFormat: String? = nil, syncMode: Bool? = nil, resolution: String? = nil, quality: String? = nil, user: String? = nil) {
        self.aspectRatio = aspectRatio
        self.outputFormat = outputFormat
        self.syncMode = syncMode
        self.resolution = resolution
        self.quality = quality
        self.user = user
    }
    enum CodingKeys: String, CodingKey {
        case aspectRatio = "aspect_ratio"
        case outputFormat = "output_format"
        case syncMode = "sync_mode"
        case resolution, quality, user
    }
}

let xaiImageModelOptionsSchema = FlexibleSchema(Schema<XAIImageModelOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        guard case .object(let object) = json else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected an object") }
        for key in ["aspect_ratio", "output_format", "sync_mode", "resolution", "quality", "user"] where object[key] == .null {
            throw InvalidArgumentError(argument: key, message: "Expected a non-null option")
        }
        let options = try JSONDecoder().decode(XAIImageModelOptions.self, from: JSONEncoder().encode(json))
        if let value = options.resolution, !["1k", "1.5k", "2k"].contains(value) { throw InvalidArgumentError(argument: "resolution", message: "Invalid image resolution") }
        if let value = options.quality, !["low", "medium", "high", "auto"].contains(value) { throw InvalidArgumentError(argument: "quality", message: "Invalid image quality") }
        return .success(value: options)
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

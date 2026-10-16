import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum XAIVideoMode: String, Codable, Sendable { case editVideo = "edit-video", extendVideo = "extend-video", referenceToVideo = "reference-to-video" }

public struct XAIVideoKeyframe: Codable, Sendable, Equatable {
    public var imageUrl: String
    public var timestampSeconds: Double
    public init(imageUrl: String, timestampSeconds: Double) { self.imageUrl = imageUrl; self.timestampSeconds = timestampSeconds }
}

public struct XAIVideoStorageOptions: Codable, Sendable, Equatable {
    public enum PublicURL: Codable, Sendable, Equatable {
        case enabled(Bool)
        case expiring(expiresAfter: Int?)
        private enum CodingKeys: String, CodingKey { case expiresAfter }
        public init(from decoder: Decoder) throws {
            if let value = try? decoder.singleValueContainer().decode(Bool.self) { self = .enabled(value) }
            else { self = .expiring(expiresAfter: try decoder.container(keyedBy: CodingKeys.self).decodeIfPresent(Int.self, forKey: .expiresAfter)) }
        }
        public func encode(to encoder: Encoder) throws {
            switch self {
            case .enabled(let value): var container = encoder.singleValueContainer(); try container.encode(value)
            case .expiring(let value): var container = encoder.container(keyedBy: CodingKeys.self); try container.encodeIfPresent(value, forKey: .expiresAfter)
            }
        }
    }
    public var filename: String
    public var expiresAfter: Int?
    public var publicUrl: PublicURL?
    public init(filename: String, expiresAfter: Int? = nil, publicUrl: PublicURL? = nil) { self.filename = filename; self.expiresAfter = expiresAfter; self.publicUrl = publicUrl }
}

public struct XAIVideoModelOptions: Codable, Sendable, Equatable {
    public var mode: XAIVideoMode?
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var resolution: String?
    public var videoUrl: String?
    public var referenceImageUrls: [String]?
    public var referenceVoiceIds: [String]?
    public var keyframes: [XAIVideoKeyframe]?
    public var storageOptions: XAIVideoStorageOptions?
    public var user: String?
    public init(mode: XAIVideoMode? = nil, pollIntervalMs: Double? = nil, pollTimeoutMs: Double? = nil, resolution: String? = nil, videoUrl: String? = nil, referenceImageUrls: [String]? = nil, referenceVoiceIds: [String]? = nil, keyframes: [XAIVideoKeyframe]? = nil, storageOptions: XAIVideoStorageOptions? = nil, user: String? = nil) {
        self.mode = mode; self.pollIntervalMs = pollIntervalMs; self.pollTimeoutMs = pollTimeoutMs; self.resolution = resolution; self.videoUrl = videoUrl
        self.referenceImageUrls = referenceImageUrls; self.referenceVoiceIds = referenceVoiceIds; self.keyframes = keyframes; self.storageOptions = storageOptions; self.user = user
    }
}

struct XAIParsedVideoOptions: Sendable {
    let options: XAIVideoModelOptions
    let extra: [String: JSONValue]
}

let xaiVideoModelOptionsSchema = FlexibleSchema(Schema<XAIParsedVideoOptions>(jsonSchemaResolver: { .object(["type": .string("object")]) }, validator: { value in
    do {
        let json = try jsonValue(from: value)
        guard case .object(let object) = json else { throw InvalidArgumentError(argument: "providerOptions", message: "Expected an object") }
        for key in ["mode", "videoUrl", "referenceImageUrls", "referenceVoiceIds", "keyframes", "storageOptions", "user"] where object[key] == .null {
            throw InvalidArgumentError(argument: key, message: "Expected a non-null option")
        }
        let options = try JSONDecoder().decode(XAIVideoModelOptions.self, from: JSONEncoder().encode(json))
        func require(_ valid: Bool, _ key: String) throws { if !valid { throw InvalidArgumentError(argument: key, message: "Invalid xAI video option") } }
        if let value = options.pollIntervalMs { try require(value > 0, "pollIntervalMs") }
        if let value = options.pollTimeoutMs { try require(value > 0, "pollTimeoutMs") }
        if let value = options.resolution { try require(["480p", "720p", "1080p"].contains(value), "resolution") }
        if let value = options.videoUrl { try require(!value.isEmpty, "videoUrl") }
        if let value = options.referenceImageUrls { try require((1...7).contains(value.count) && value.allSatisfy { !$0.isEmpty }, "referenceImageUrls") }
        if let value = options.referenceVoiceIds { try require(value.count <= 3 && value.allSatisfy { !$0.isEmpty }, "referenceVoiceIds") }
        if let value = options.keyframes { try require(value.count <= 4 && value.allSatisfy { !$0.imageUrl.isEmpty && $0.timestampSeconds > 0 }, "keyframes") }
        if let storage = options.storageOptions {
            try require(!storage.filename.isEmpty, "storageOptions.filename")
            if let value = storage.expiresAfter { try require((1...2_592_000).contains(value), "storageOptions.expiresAfter") }
            if case .expiring(let value) = storage.publicUrl, let value { try require((3600...2_592_000).contains(value), "storageOptions.publicUrl.expiresAfter") }
        }
        let known = Set(["mode", "pollIntervalMs", "pollTimeoutMs", "resolution", "videoUrl", "referenceImageUrls", "referenceVoiceIds", "keyframes", "storageOptions", "user"])
        return .success(value: .init(options: options, extra: object.filter { !known.contains($0.key) }))
    } catch { return .failure(error: TypeValidationError.wrap(value: value, cause: error)) }
}))

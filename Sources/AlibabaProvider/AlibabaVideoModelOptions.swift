import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct AlibabaVideoModelOptions: Sendable, Equatable, Decodable {
    public enum ShotType: String, Sendable, Equatable, Decodable { case single, multi }
    public enum Ratio: String, Sendable, Equatable, Decodable {
        case adaptive
        case sixteenByNine = "16:9"
        case nineBySixteen = "9:16"
        case square = "1:1"
        case fourByThree = "4:3"
        case threeByFour = "3:4"
    }
    public struct Media: Sendable, Equatable, Decodable {
        public enum Kind: String, Sendable, Equatable, Decodable {
            case referenceImage = "reference_image"
            case referenceVideo = "reference_video"
            case referenceAudio = "reference_audio"
            case firstFrame = "first_frame"
            case lastFrame = "last_frame"
            case file, link
        }
        public var type: Kind
        public var url: String
        public var referenceVoice: String?

        public init(type: Kind, url: String, referenceVoice: String? = nil) {
            self.type = type
            self.url = url
            self.referenceVoice = referenceVoice
        }
    }

    public var negativePrompt: String?
    public var audioUrl: String?
    public var promptExtend: Bool?
    public var shotType: ShotType?
    public var watermark: Bool?
    public var audio: Bool?
    public var referenceUrls: [String]?
    public var media: [Media]?
    public var ratio: Ratio?
    public var pollIntervalMs: Double?
    public var pollTimeoutMs: Double?
    public var additionalOptions: JSONObject

    public init(
        negativePrompt: String? = nil,
        audioUrl: String? = nil,
        promptExtend: Bool? = nil,
        shotType: ShotType? = nil,
        watermark: Bool? = nil,
        audio: Bool? = nil,
        referenceUrls: [String]? = nil,
        media: [Media]? = nil,
        ratio: Ratio? = nil,
        pollIntervalMs: Double? = nil,
        pollTimeoutMs: Double? = nil,
        additionalOptions: JSONObject = [:]
    ) {
        self.negativePrompt = negativePrompt
        self.audioUrl = audioUrl
        self.promptExtend = promptExtend
        self.shotType = shotType
        self.watermark = watermark
        self.audio = audio
        self.referenceUrls = referenceUrls
        self.media = media
        self.ratio = ratio
        self.pollIntervalMs = pollIntervalMs
        self.pollTimeoutMs = pollTimeoutMs
        self.additionalOptions = additionalOptions
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case negativePrompt, audioUrl, promptExtend, shotType, watermark, audio
        case referenceUrls, media, ratio, pollIntervalMs, pollTimeoutMs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        negativePrompt = try container.decodeIfPresent(String.self, forKey: .negativePrompt)
        audioUrl = try container.decodeIfPresent(String.self, forKey: .audioUrl)
        promptExtend = try container.decodeIfPresent(Bool.self, forKey: .promptExtend)
        shotType = try container.decodeIfPresent(ShotType.self, forKey: .shotType)
        watermark = try container.decodeIfPresent(Bool.self, forKey: .watermark)
        audio = try container.decodeIfPresent(Bool.self, forKey: .audio)
        referenceUrls = try container.decodeIfPresent([String].self, forKey: .referenceUrls)
        media = try container.decodeIfPresent([Media].self, forKey: .media)
        ratio = try container.decodeIfPresent(Ratio.self, forKey: .ratio)
        pollIntervalMs = try container.decodeIfPresent(Double.self, forKey: .pollIntervalMs)
        pollTimeoutMs = try container.decodeIfPresent(Double.self, forKey: .pollTimeoutMs)
        for (key, value) in [(CodingKeys.pollIntervalMs, pollIntervalMs), (.pollTimeoutMs, pollTimeoutMs)] {
            if let value, !value.isFinite || value <= 0 {
                throw DecodingError.dataCorruptedError(forKey: key, in: container, debugDescription: "Expected a positive number")
            }
        }
        let raw = try JSONObject(from: decoder)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        additionalOptions = raw.filter { !known.contains($0.key) }
    }
}

let alibabaVideoModelOptionsSchema = FlexibleSchema(
    Schema<AlibabaVideoModelOptions>.codable(AlibabaVideoModelOptions.self, jsonSchema: ["type": "object"])
)

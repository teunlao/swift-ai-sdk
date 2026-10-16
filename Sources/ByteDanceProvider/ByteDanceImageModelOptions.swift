import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ByteDanceImageModelOptions: Decodable, Sendable {
    public enum OutputFormat: String, Decodable, Sendable { case png, jpeg }
    public enum SequentialImageGeneration: String, Decodable, Sendable { case auto, disabled }
    public enum OptimizePromptMode: String, Decodable, Sendable { case standard, fast }

    public let watermark: Bool?
    public let outputFormat: OutputFormat?
    public let size: String?
    public let sequentialImageGeneration: SequentialImageGeneration?
    public let maxImages: Int?
    public let optimizePromptMode: OptimizePromptMode?
    public let additionalOptions: JSONObject

    public init(
        watermark: Bool? = nil,
        outputFormat: OutputFormat? = nil,
        size: String? = nil,
        sequentialImageGeneration: SequentialImageGeneration? = nil,
        maxImages: Int? = nil,
        optimizePromptMode: OptimizePromptMode? = nil,
        additionalOptions: JSONObject = [:]
    ) throws {
        if let maxImages, maxImages <= 0 {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "maxImages must be a positive integer"))
        }
        self.watermark = watermark
        self.outputFormat = outputFormat
        self.size = size
        self.sequentialImageGeneration = sequentialImageGeneration
        self.maxImages = maxImages
        self.optimizePromptMode = optimizePromptMode
        self.additionalOptions = additionalOptions
    }

    enum CodingKeys: String, CodingKey, CaseIterable {
        case watermark, outputFormat, size, sequentialImageGeneration, maxImages, optimizePromptMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try decoder.singleValueContainer().decode(JSONObject.self)
        let known = Set(CodingKeys.allCases.map(\.rawValue))
        try self.init(
            watermark: container.decodeIfPresent(Bool.self, forKey: .watermark),
            outputFormat: container.decodeIfPresent(OutputFormat.self, forKey: .outputFormat),
            size: container.decodeIfPresent(String.self, forKey: .size),
            sequentialImageGeneration: container.decodeIfPresent(SequentialImageGeneration.self, forKey: .sequentialImageGeneration),
            maxImages: container.decodeIfPresent(Int.self, forKey: .maxImages),
            optimizePromptMode: container.decodeIfPresent(OptimizePromptMode.self, forKey: .optimizePromptMode),
            additionalOptions: raw.filter { !known.contains($0.key) }
        )
    }
}

let byteDanceImageModelOptionsSchema = FlexibleSchema(
    Schema<ByteDanceImageModelOptions>.codable(ByteDanceImageModelOptions.self, jsonSchema: .object(["type": .string("object")]))
)

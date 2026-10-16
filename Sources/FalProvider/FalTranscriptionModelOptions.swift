import Foundation
import AISDKProviderUtils

public struct FalTranscriptionModelOptions: Decodable, Sendable {
    public enum ChunkLevel: String, Codable, Sendable {
        case segment
        case word
    }

    public let language: String?
    public let diarize: Bool?
    public let chunkLevel: ChunkLevel?
    public let version: String?
    public let batchSize: Double?
    public let numSpeakers: Double?

    public init(
        language: String? = "en",
        diarize: Bool? = true,
        chunkLevel: ChunkLevel? = .segment,
        version: String? = "3",
        batchSize: Double? = 64,
        numSpeakers: Double? = nil
    ) throws {
        if let version, version != "3" {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "version must be '3'"))
        }
        self.language = language
        self.diarize = diarize
        self.chunkLevel = chunkLevel
        self.version = version
        self.batchSize = batchSize
        self.numSpeakers = numSpeakers
    }

    enum CodingKeys: String, CodingKey {
        case language, diarize, chunkLevel, version, batchSize, numSpeakers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            language: container.contains(.language) ? container.decodeIfPresent(String.self, forKey: .language) : "en",
            diarize: container.contains(.diarize) ? container.decodeIfPresent(Bool.self, forKey: .diarize) : true,
            chunkLevel: container.contains(.chunkLevel) ? container.decodeIfPresent(ChunkLevel.self, forKey: .chunkLevel) : .segment,
            version: container.contains(.version) ? container.decodeIfPresent(String.self, forKey: .version) : "3",
            batchSize: container.contains(.batchSize) ? container.decodeIfPresent(Double.self, forKey: .batchSize) : 64,
            numSpeakers: container.decodeIfPresent(Double.self, forKey: .numSpeakers)
        )
    }
}

let falTranscriptionModelOptionsSchema = FlexibleSchema(
    Schema<FalTranscriptionModelOptions>.codable(
        FalTranscriptionModelOptions.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

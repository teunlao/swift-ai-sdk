import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ProdiaLanguageModelOptions: Decodable, Sendable {
    public let aspectRatio: String?
    public init(aspectRatio: String? = nil) { self.aspectRatio = aspectRatio }
    private enum CodingKeys: String, CodingKey { case aspectRatio }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if container.contains(.aspectRatio) {
            let value = try container.decode(String.self, forKey: .aspectRatio)
            guard ["1:1", "2:3", "3:2", "4:5", "5:4", "4:7", "7:4", "9:16", "16:9", "9:21", "21:9"].contains(value) else {
                throw DecodingError.dataCorruptedError(forKey: .aspectRatio, in: container, debugDescription: "Unsupported Prodia aspect ratio")
            }
            aspectRatio = value
        } else { aspectRatio = nil }
    }
}

let prodiaLanguageModelOptionsSchema = FlexibleSchema(
    Schema<ProdiaLanguageModelOptions>.codable(ProdiaLanguageModelOptions.self, jsonSchema: .object(["type": .string("object")]))
)

import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct ProdiaVideoModelOptions: Decodable, Sendable {
    public let resolution: String?
    public init(resolution: String? = nil) { self.resolution = resolution }
    private enum CodingKeys: String, CodingKey { case resolution }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        resolution = container.contains(.resolution) ? try container.decode(String.self, forKey: .resolution) : nil
    }
}

let prodiaVideoModelOptionsSchema = FlexibleSchema(
    Schema<ProdiaVideoModelOptions>.codable(ProdiaVideoModelOptions.self, jsonSchema: .object(["type": .string("object")]))
)

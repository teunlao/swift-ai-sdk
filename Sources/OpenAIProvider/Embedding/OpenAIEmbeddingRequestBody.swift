import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIEmbeddingRequestBody: Encodable, Sendable {
    let model: String
    let input: [String]
    let encodingFormat: String = "float"
    let dimensions: Int?
    let user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case encodingFormat = "encoding_format"
        case dimensions
        case user
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(input, forKey: .input)
        try container.encode(encodingFormat, forKey: .encodingFormat)
        try container.encodeIfPresent(dimensions, forKey: .dimensions)
        try container.encodeIfPresent(user, forKey: .user)
    }
}

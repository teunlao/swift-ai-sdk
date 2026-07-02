import Foundation

/**
 File data as a v4 tagged discriminated union.

 Port of `@ai-sdk/provider/src/shared/v4/shared-v4-file-data.ts`.
 */
public enum SharedV4FileData: Sendable, Equatable, Codable {
    case data(Data)
    case base64(String)
    case url(URL)
    case reference(SharedV4ProviderReference)
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case url
        case reference
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "data":
            let value = try container.decode(String.self, forKey: .data)
            self = .base64(value)
        case "url":
            self = .url(try container.decode(URL.self, forKey: .url))
        case "reference":
            self = .reference(try container.decode(SharedV4ProviderReference.self, forKey: .reference))
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown SharedV4FileData type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .data(data):
            try container.encode("data", forKey: .type)
            try container.encode(data, forKey: .data)
        case let .base64(base64):
            try container.encode("data", forKey: .type)
            try container.encode(base64, forKey: .data)
        case let .url(url):
            try container.encode("url", forKey: .type)
            try container.encode(url, forKey: .url)
        case let .reference(reference):
            try container.encode("reference", forKey: .type)
            try container.encode(reference, forKey: .reference)
        case let .text(text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

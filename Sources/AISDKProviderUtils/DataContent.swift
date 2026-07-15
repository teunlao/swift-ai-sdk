import Foundation

/**
 Data content representation mirroring `@ai-sdk/provider-utils`.
 */
public enum DataContent: Sendable {
    /// Base64-encoded string
    case string(String)
    /// Raw binary data
    case data(Data)
}

/// Union type for data content or URL inputs (matches upstream usage across packages).
public enum DataContentOrURL: Sendable, Equatable, Codable {
    case data(Data)
    case string(String)
    case url(URL)
    case reference(ProviderReference)
    case text(String)

    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case value
        case url
        case reference
        case text
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "data":
            let base64 = try container.decode(String.self, forKey: .data)
            guard let data = Data(base64Encoded: base64) else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data,
                    in: container,
                    debugDescription: "Invalid base64 string"
                )
            }
            self = .data(data)
        case "string":
            let value = try container.decode(String.self, forKey: .value)
            self = .string(value)
        case "url":
            let url = try container.decode(URL.self, forKey: .url)
            self = .url(url)
        case "reference":
            self = .reference(try container.decode(ProviderReference.self, forKey: .reference))
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown DataContentOrURL type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .data(let data):
            try container.encode("data", forKey: .type)
            try container.encode(data.base64EncodedString(), forKey: .data)
        case .string(let value):
            try container.encode("string", forKey: .type)
            try container.encode(value, forKey: .value)
        case .url(let url):
            try container.encode("url", forKey: .type)
            try container.encode(url, forKey: .url)
        case .reference(let reference):
            try container.encode("reference", forKey: .type)
            try container.encode(reference, forKey: .reference)
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        }
    }
}

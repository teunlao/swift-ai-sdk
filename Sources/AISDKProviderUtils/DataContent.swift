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

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let string = try? container.decode(String.self) {
            if let url = URL(string: string), url.scheme != nil {
                self = .url(url)
            } else {
                self = .string(string)
            }
            return
        }

        if let data = try? container.decode(Data.self) {
            self = .data(data)
            return
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Cannot decode DataContentOrURL"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .url(let url):
            try container.encode(url.absoluteString)
        case .data(let data):
            try container.encode(data.base64EncodedString())
        }
    }
}

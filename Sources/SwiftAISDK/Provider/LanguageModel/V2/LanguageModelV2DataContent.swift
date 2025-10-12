import Foundation

/**
 Data content for file parts. Can be binary data, base64 encoded string, or URL.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV2DataContent =
   | Uint8Array
   | { type: 'base64'; data: string }
   | { type: 'url'; url: string };
 ```
 */
public enum LanguageModelV2DataContent: Sendable, Equatable {
    /// Binary data (equivalent to Uint8Array in TypeScript)
    case data(Data)

    /// Base64 encoded string
    case base64(String)

    /// URL reference
    case url(URL)
}

// MARK: - Codable conformance
extension LanguageModelV2DataContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case url
    }

    public init(from decoder: Decoder) throws {
        // Try to decode as structured object first
        if let container = try? decoder.container(keyedBy: CodingKeys.self),
           let type = try? container.decode(String.self, forKey: .type) {
            switch type {
            case "base64":
                let data = try container.decode(String.self, forKey: .data)
                self = .base64(data)
            case "url":
                let urlString = try container.decode(String.self, forKey: .url)
                guard let url = URL(string: urlString) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .url,
                        in: container,
                        debugDescription: "Invalid URL string: \(urlString)"
                    )
                }
                self = .url(url)
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unknown type: \(type)"
                )
            }
        } else {
            // Fallback: try to decode as raw Data (Uint8Array equivalent)
            let container = try decoder.singleValueContainer()
            let data = try container.decode(Data.self)
            self = .data(data)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .data(let data):
            var container = encoder.singleValueContainer()
            try container.encode(data)
        case .base64(let string):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("base64", forKey: .type)
            try container.encode(string, forKey: .data)
        case .url(let url):
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode("url", forKey: .type)
            try container.encode(url.absoluteString, forKey: .url)
        }
    }
}

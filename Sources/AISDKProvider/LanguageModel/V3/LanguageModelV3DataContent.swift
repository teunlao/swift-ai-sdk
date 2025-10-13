import Foundation

/**
 Data content for file parts. Can be binary data, base64 encoded string, or URL.

 TypeScript equivalent:
 ```typescript
 export type LanguageModelV3DataContent = Uint8Array | string | URL;
 ```
 */
public enum LanguageModelV3DataContent: Sendable, Equatable {
    /// Binary data (equivalent to Uint8Array in TypeScript)
    case data(Data)

    /// Base64 encoded string
    case base64(String)

    /// URL reference
    case url(URL)
}

// MARK: - Codable conformance
extension LanguageModelV3DataContent: Codable {
    private enum CodingKeys: String, CodingKey {
        case type
        case data
        case url
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        // Try to decode as Data (Uint8Array equivalent) first
        if let data = try? container.decode(Data.self) {
            self = .data(data)
            return
        }

        // Try to decode as String (base64 or URL)
        if let string = try? container.decode(String.self) {
            // Check if it's a valid URL
            if let url = URL(string: string), url.scheme != nil {
                self = .url(url)
            } else {
                // Otherwise, treat as base64 string
                self = .base64(string)
            }
            return
        }

        // Fallback: try structured object for backward compatibility
        if let keyed = try? decoder.container(keyedBy: CodingKeys.self),
           let type = try? keyed.decode(String.self, forKey: .type) {
            switch type {
            case "base64":
                let data = try keyed.decode(String.self, forKey: .data)
                self = .base64(data)
                return
            case "url":
                let urlString = try keyed.decode(String.self, forKey: .url)
                guard let url = URL(string: urlString) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .url,
                        in: keyed,
                        debugDescription: "Invalid URL string: \(urlString)"
                    )
                }
                self = .url(url)
                return
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: keyed,
                    debugDescription: "Unknown type: \(type)"
                )
            }
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Cannot decode LanguageModelV3DataContent"
            )
        )
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .data(let data):
            // Encode as raw Data (Uint8Array equivalent)
            try container.encode(data)
        case .base64(let string):
            // Encode as plain string (NO wrapper!)
            try container.encode(string)
        case .url(let url):
            // Encode as plain URL string (NO wrapper!)
            try container.encode(url.absoluteString)
        }
    }
}

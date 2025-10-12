import Foundation

/**
 A source that has been used as input to generate the response.

 TypeScript equivalent (discriminated union):
 ```typescript
 export type LanguageModelV3Source =
   | {
       type: 'source';
       sourceType: 'url';
       id: string;
       url: string;
       title?: string;
       providerMetadata?: SharedV3ProviderMetadata;
     }
   | {
       type: 'source';
       sourceType: 'document';
       id: string;
       mediaType: string;
       title: string;
       filename?: string;
       providerMetadata?: SharedV3ProviderMetadata;
     };
 ```
 */
public enum LanguageModelV3Source: Sendable, Equatable, Codable {
    /// URL sources reference web content
    case url(id: String, url: String, title: String?, providerMetadata: SharedV3ProviderMetadata?)

    /// Document sources reference files/documents
    case document(
        id: String,
        mediaType: String,
        title: String,
        filename: String?,
        providerMetadata: SharedV3ProviderMetadata?
    )

    private enum CodingKeys: String, CodingKey {
        case type
        case sourceType
        case id
        case url
        case title
        case mediaType
        case filename
        case providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceType = try container.decode(String.self, forKey: .sourceType)
        let id = try container.decode(String.self, forKey: .id)
        let providerMetadata = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerMetadata)

        switch sourceType {
        case "url":
            let url = try container.decode(String.self, forKey: .url)
            let title = try container.decodeIfPresent(String.self, forKey: .title)
            self = .url(id: id, url: url, title: title, providerMetadata: providerMetadata)
        case "document":
            let mediaType = try container.decode(String.self, forKey: .mediaType)
            let title = try container.decode(String.self, forKey: .title)
            let filename = try container.decodeIfPresent(String.self, forKey: .filename)
            self = .document(
                id: id,
                mediaType: mediaType,
                title: title,
                filename: filename,
                providerMetadata: providerMetadata
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .sourceType,
                in: container,
                debugDescription: "Unknown sourceType: \(sourceType)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("source", forKey: .type)

        switch self {
        case let .url(id, url, title, providerMetadata):
            try container.encode("url", forKey: .sourceType)
            try container.encode(id, forKey: .id)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(title, forKey: .title)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        case let .document(id, mediaType, title, filename, providerMetadata):
            try container.encode("document", forKey: .sourceType)
            try container.encode(id, forKey: .id)
            try container.encode(mediaType, forKey: .mediaType)
            try container.encode(title, forKey: .title)
            try container.encodeIfPresent(filename, forKey: .filename)
            try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
        }
    }
}

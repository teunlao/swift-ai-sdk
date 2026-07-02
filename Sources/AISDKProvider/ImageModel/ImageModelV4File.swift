import Foundation

/**
 An image file that can be used for image editing or variation generation.

 Port of `@ai-sdk/provider/src/image-model/v4/image-model-v4-file.ts`.
 */
public enum ImageModelV4File: Sendable, Equatable, Codable {
    case file(mediaType: String, data: ImageModelV4FileData, providerOptions: SharedV4ProviderMetadata?)
    case url(url: String, providerOptions: SharedV4ProviderMetadata?)

    private enum CodingKeys: String, CodingKey {
        case type
        case mediaType
        case data
        case url
        case providerOptions
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "file":
            self = .file(
                mediaType: try container.decode(String.self, forKey: .mediaType),
                data: try container.decode(ImageModelV4FileData.self, forKey: .data),
                providerOptions: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerOptions)
            )
        case "url":
            self = .url(
                url: try container.decode(String.self, forKey: .url),
                providerOptions: try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerOptions)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unexpected ImageModelV4File type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case let .file(mediaType, data, providerOptions):
            try container.encode("file", forKey: .type)
            try container.encode(mediaType, forKey: .mediaType)
            try container.encode(data, forKey: .data)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        case let .url(url, providerOptions):
            try container.encode("url", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
        }
    }
}

public enum ImageModelV4FileData: Sendable, Equatable, Codable {
    case base64(String)
    case binary(Data)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .base64(string)
        } else if let data = try? container.decode(Data.self) {
            self = .binary(data)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected String or Data for ImageModelV4File data"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .base64(let string):
            try container.encode(string)
        case .binary(let data):
            try container.encode(data)
        }
    }
}

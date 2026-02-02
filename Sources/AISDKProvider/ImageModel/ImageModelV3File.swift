import Foundation

/**
 An image file that can be used for image editing or variation generation.

 Port of `@ai-sdk/provider/src/image-model/v3/image-model-v3-file.ts`.
 */
public enum ImageModelV3File: Sendable, Equatable, Codable {
    case file(mediaType: String, data: ImageModelV3FileData, providerOptions: SharedV3ProviderMetadata?)
    case url(url: String, providerOptions: SharedV3ProviderMetadata?)

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
            let mediaType = try container.decode(String.self, forKey: .mediaType)
            let data = try container.decode(ImageModelV3FileData.self, forKey: .data)
            let providerOptions = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerOptions)
            self = .file(mediaType: mediaType, data: data, providerOptions: providerOptions)
        case "url":
            let url = try container.decode(String.self, forKey: .url)
            let providerOptions = try container.decodeIfPresent(SharedV3ProviderMetadata.self, forKey: .providerOptions)
            self = .url(url: url, providerOptions: providerOptions)
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unexpected ImageModelV3File type: \(type)"
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

public enum ImageModelV3FileData: Sendable, Equatable, Codable {
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
                debugDescription: "Expected String or Data for ImageModelV3File data"
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

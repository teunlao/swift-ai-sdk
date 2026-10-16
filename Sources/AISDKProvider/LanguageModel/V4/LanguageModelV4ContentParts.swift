import Foundation

/**
 A reference supporting generated text, separate from retrieved sources.

 Port of `@ai-sdk/provider/src/language-model/v4/language-model-v4-citation.ts`.
 */
public struct LanguageModelV4Citation: Sendable, Equatable, Codable {
    public let source: LanguageModelV4Source
    public let startIndex: Int?
    public let endIndex: Int?
    public let citedText: String?

    public init(
        source: LanguageModelV4Source,
        startIndex: Int? = nil,
        endIndex: Int? = nil,
        citedText: String? = nil
    ) {
        self.source = source
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.citedText = citedText
    }
}

public struct LanguageModelV4Text: Sendable, Equatable, Codable {
    public let type: String = "text"
    public let text: String
    public let citations: [LanguageModelV4Citation]?
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        text: String,
        citations: [LanguageModelV4Citation]? = nil,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.text = text
        self.citations = citations
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey { case type, text, citations, providerMetadata }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        citations = try container.decodeIfPresent([LanguageModelV4Citation].self, forKey: .citations)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(citations, forKey: .citations)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

public struct LanguageModelV4Reasoning: Sendable, Equatable, Codable {
    public let type: String = "reasoning"
    public let text: String
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(text: String, providerMetadata: SharedV4ProviderMetadata? = nil) {
        self.text = text
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey { case type, text, providerMetadata }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = try container.decode(String.self, forKey: .text)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

public struct LanguageModelV4CustomContent: Sendable, Equatable, Codable {
    public let type: String = "custom"
    public let kind: String
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(kind: String, providerMetadata: SharedV4ProviderMetadata? = nil) {
        self.kind = kind
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey { case type, kind, providerMetadata }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(String.self, forKey: .kind)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(kind, forKey: .kind)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

public struct LanguageModelV4File: Sendable, Equatable, Codable {
    public let type: String = "file"
    public let mediaType: String
    public let data: LanguageModelV4FileData
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        mediaType: String,
        data: LanguageModelV4FileData,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.mediaType = mediaType
        self.data = data
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey { case type, mediaType, data, providerMetadata }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        data = try container.decode(LanguageModelV4FileData.self, forKey: .data)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

public struct LanguageModelV4ReasoningFile: Sendable, Equatable, Codable {
    public let type: String = "reasoning-file"
    public let mediaType: String
    public let data: LanguageModelV4FileData
    public let providerMetadata: SharedV4ProviderMetadata?

    public init(
        mediaType: String,
        data: LanguageModelV4FileData,
        providerMetadata: SharedV4ProviderMetadata? = nil
    ) {
        self.mediaType = mediaType
        self.data = data
        self.providerMetadata = providerMetadata
    }

    private enum CodingKeys: String, CodingKey { case type, mediaType, data, providerMetadata }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mediaType = try container.decode(String.self, forKey: .mediaType)
        data = try container.decode(LanguageModelV4FileData.self, forKey: .data)
        providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(mediaType, forKey: .mediaType)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(providerMetadata, forKey: .providerMetadata)
    }
}

public enum LanguageModelV4FileData: Sendable, Equatable, Codable {
    case data(Data)
    case base64(String)
    /// `originalUrl` keeps the source string when parsing it into a `URL` changed it.
    case url(URL, originalUrl: String? = nil)

    private enum CodingKeys: String, CodingKey { case type, data, url, originalUrl }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "data":
            self = .base64(try container.decode(String.self, forKey: .data))
        case "url":
            self = .url(
                try container.decode(URL.self, forKey: .url),
                originalUrl: try container.decodeIfPresent(String.self, forKey: .originalUrl)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unknown LanguageModelV4FileData type: \(type)"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .data(let data):
            try container.encode("data", forKey: .type)
            try container.encode(data, forKey: .data)
        case .base64(let base64):
            try container.encode("data", forKey: .type)
            try container.encode(base64, forKey: .data)
        case let .url(url, originalUrl):
            try container.encode("url", forKey: .type)
            try container.encode(url, forKey: .url)
            try container.encodeIfPresent(originalUrl, forKey: .originalUrl)
        }
    }
}

public enum LanguageModelV4Source: Sendable, Equatable, Codable {
    case url(id: String, url: String, title: String?, providerMetadata: SharedV4ProviderMetadata?)
    case document(id: String, mediaType: String, title: String, filename: String?, providerMetadata: SharedV4ProviderMetadata?)

    private enum CodingKeys: String, CodingKey {
        case type, sourceType, id, url, title, mediaType, filename, providerMetadata
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let sourceType = try container.decode(String.self, forKey: .sourceType)
        let id = try container.decode(String.self, forKey: .id)
        let providerMetadata = try container.decodeIfPresent(SharedV4ProviderMetadata.self, forKey: .providerMetadata)

        switch sourceType {
        case "url":
            self = .url(
                id: id,
                url: try container.decode(String.self, forKey: .url),
                title: try container.decodeIfPresent(String.self, forKey: .title),
                providerMetadata: providerMetadata
            )
        case "document":
            self = .document(
                id: id,
                mediaType: try container.decode(String.self, forKey: .mediaType),
                title: try container.decode(String.self, forKey: .title),
                filename: try container.decodeIfPresent(String.self, forKey: .filename),
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

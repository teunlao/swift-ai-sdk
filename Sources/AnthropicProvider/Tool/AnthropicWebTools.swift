import Foundation
import AISDKProvider
import AISDKProviderUtils


public struct AnthropicWebFetchToolResult: Codable, Equatable, Sendable {
    public struct Content: Codable, Equatable, Sendable {
        public struct Citations: Codable, Equatable, Sendable {
            public let enabled: Bool
        }

        public struct Source: Codable, Equatable, Sendable {
            public let type: String
            public let mediaType: String
            public let data: String

            private enum CodingKeys: String, CodingKey {
                case type
                case mediaType
                case data
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                type = try container.decode(String.self, forKey: .type)
                mediaType = try container.decode(String.self, forKey: .mediaType)
                data = try container.decode(String.self, forKey: .data)

                switch type {
                case "base64":
                    if mediaType != "application/pdf" {
                        throw DecodingError.dataCorruptedError(
                            forKey: .mediaType,
                            in: container,
                            debugDescription: "Expected mediaType 'application/pdf' for base64 source"
                        )
                    }
                case "text":
                    if mediaType != "text/plain" {
                        throw DecodingError.dataCorruptedError(
                            forKey: .mediaType,
                            in: container,
                            debugDescription: "Expected mediaType 'text/plain' for text source"
                        )
                    }
                default:
                    throw DecodingError.dataCorruptedError(
                        forKey: .type,
                        in: container,
                        debugDescription: "Unexpected source type: \(type)"
                    )
                }
            }
        }

        public let type: String
        public let title: String?
        public let citations: Citations?
        public let source: Source

        private enum CodingKeys: String, CodingKey {
            case type
            case title
            case citations
            case source
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            type = try container.decode(String.self, forKey: .type)
            if type != "document" {
                throw DecodingError.dataCorruptedError(
                    forKey: .type,
                    in: container,
                    debugDescription: "Unexpected content type: \(type)"
                )
            }

            guard container.contains(.title) else {
                throw DecodingError.keyNotFound(
                    CodingKeys.title,
                    DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required field: title")
                )
            }
            title = try container.decodeIfPresent(String.self, forKey: .title)

            if container.contains(.citations), (try container.decodeNil(forKey: .citations)) {
                throw DecodingError.dataCorruptedError(
                    forKey: .citations,
                    in: container,
                    debugDescription: "citations must be an object when present"
                )
            }
            citations = try container.decodeIfPresent(Citations.self, forKey: .citations)

            source = try container.decode(Source.self, forKey: .source)
        }
    }

    public let type: String
    public let url: String
    public let content: Content
    public let retrievedAt: String?

    private enum CodingKeys: String, CodingKey {
        case type
        case url
        case content
        case retrievedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try container.decode(String.self, forKey: .type)
        if type != "web_fetch_result" {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unexpected result type: \(type)"
            )
        }

        url = try container.decode(String.self, forKey: .url)
        content = try container.decode(Content.self, forKey: .content)

        guard container.contains(.retrievedAt) else {
            throw DecodingError.keyNotFound(
                CodingKeys.retrievedAt,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required field: retrievedAt")
            )
        }
        retrievedAt = try container.decodeIfPresent(String.self, forKey: .retrievedAt)
    }
}

public struct AnthropicWebSearchToolResult: Codable, Equatable, Sendable {
    public let url: String
    public let title: String?
    public let pageAge: String?
    public let encryptedContent: String
    public let type: String

    private enum CodingKeys: String, CodingKey {
        case url
        case title
        case pageAge
        case encryptedContent
        case type
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        url = try container.decode(String.self, forKey: .url)

        guard container.contains(.title) else {
            throw DecodingError.keyNotFound(
                CodingKeys.title,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required field: title")
            )
        }
        title = try container.decodeIfPresent(String.self, forKey: .title)

        guard container.contains(.pageAge) else {
            throw DecodingError.keyNotFound(
                CodingKeys.pageAge,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Missing required field: pageAge")
            )
        }
        pageAge = try container.decodeIfPresent(String.self, forKey: .pageAge)

        encryptedContent = try container.decode(String.self, forKey: .encryptedContent)
        type = try container.decode(String.self, forKey: .type)

        if type != "web_search_result" {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "Unexpected result type: \(type)"
            )
        }
    }
}

public struct AnthropicWebFetchToolArgs: Codable, Sendable, Equatable {
    public struct Citations: Codable, Sendable, Equatable {
        public var enabled: Bool?

        public init(enabled: Bool? = nil) {
            self.enabled = enabled
        }
    }

    public var maxUses: Int?
    public var allowedDomains: [String]?
    public var blockedDomains: [String]?
    public var citations: Citations?
    public var maxContentTokens: Int?

    public init(
        maxUses: Int? = nil,
        allowedDomains: [String]? = nil,
        blockedDomains: [String]? = nil,
        citations: Citations? = nil,
        maxContentTokens: Int? = nil
    ) {
        self.maxUses = maxUses
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.citations = citations
        self.maxContentTokens = maxContentTokens
    }

}

public let anthropicWebFetch20250910ArgsSchema = FlexibleSchema(
    Schema<AnthropicWebFetchToolArgs>.codable(
        AnthropicWebFetchToolArgs.self,
        jsonSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "maxUses": .object(["type": .string("number")]),
                "allowedDomains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
                "blockedDomains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
                "citations": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("enabled")]),
                    "properties": .object([
                        "enabled": .object(["type": .string("boolean")])
                    ]),
                ]),
                "maxContentTokens": .object(["type": .string("number")]),
            ]),
        ])
    )
)

public let anthropicWebFetch20250910OutputSchema = FlexibleSchema(
    Schema<AnthropicWebFetchToolResult>.codable(
        AnthropicWebFetchToolResult.self,
        jsonSchema: .object([
            "type": .string("object"),
            "required": .array([.string("type"), .string("url"), .string("content"), .string("retrievedAt")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object(["const": .string("web_fetch_result")]),
                "url": .object(["type": .string("string")]),
                "content": .object([
                    "type": .string("object"),
                    "required": .array([.string("type"), .string("title"), .string("source")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "type": .object(["const": .string("document")]),
                        "title": .object(["type": .array([.string("string"), .string("null")])]),
                        "citations": .object([
                            "type": .string("object"),
                            "required": .array([.string("enabled")]),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "enabled": .object(["type": .string("boolean")])
                            ]),
                        ]),
                        "source": .object([
                            "oneOf": .array([
                                .object([
                                    "type": .string("object"),
                                    "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "type": .object(["const": .string("base64")]),
                                        "mediaType": .object(["const": .string("application/pdf")]),
                                        "data": .object(["type": .string("string")]),
                                    ]),
                                ]),
                                .object([
                                    "type": .string("object"),
                                    "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "type": .object(["const": .string("text")]),
                                        "mediaType": .object(["const": .string("text/plain")]),
                                        "data": .object(["type": .string("string")]),
                                    ]),
                                ]),
                            ])
                        ]),
                    ]),
                ]),
                "retrievedAt": .object(["type": .array([.string("string"), .string("null")])]),
            ]),
        ])
    )
)

private let anthropicWebFetch20250910ToolOutputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "required": .array([.string("type"), .string("url"), .string("content"), .string("retrievedAt")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object(["const": .string("web_fetch_result")]),
                "url": .object(["type": .string("string")]),
                "content": .object([
                    "type": .string("object"),
                    "required": .array([.string("type"), .string("title"), .string("source")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "type": .object(["const": .string("document")]),
                        "title": .object(["type": .array([.string("string"), .string("null")])]),
                        "citations": .object([
                            "type": .string("object"),
                            "required": .array([.string("enabled")]),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "enabled": .object(["type": .string("boolean")])
                            ]),
                        ]),
                        "source": .object([
                            "oneOf": .array([
                                .object([
                                    "type": .string("object"),
                                    "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "type": .object(["const": .string("base64")]),
                                        "mediaType": .object(["const": .string("application/pdf")]),
                                        "data": .object(["type": .string("string")]),
                                    ]),
                                ]),
                                .object([
                                    "type": .string("object"),
                                    "required": .array([.string("type"), .string("mediaType"), .string("data")]),
                                    "additionalProperties": .bool(false),
                                    "properties": .object([
                                        "type": .object(["const": .string("text")]),
                                        "mediaType": .object(["const": .string("text/plain")]),
                                        "data": .object(["type": .string("string")]),
                                    ]),
                                ]),
                            ])
                        ]),
                    ]),
                ]),
                "retrievedAt": .object(["type": .array([.string("string"), .string("null")])]),
            ]),
        ])
    )
)

public struct AnthropicWebSearchToolArgs: Codable, Sendable, Equatable {
    public struct UserLocation: Codable, Sendable, Equatable {
        public var type: String?
        public var city: String?
        public var region: String?
        public var country: String?
        public var timezone: String?

        public init(
            type: String? = nil,
            city: String? = nil,
            region: String? = nil,
            country: String? = nil,
            timezone: String? = nil
        ) {
            self.type = type
            self.city = city
            self.region = region
            self.country = country
            self.timezone = timezone
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case city
            case region
            case country
            case timezone
        }
    }

    public var maxUses: Int?
    public var allowedDomains: [String]?
    public var blockedDomains: [String]?
    public var userLocation: UserLocation?

    public init(
        maxUses: Int? = nil,
        allowedDomains: [String]? = nil,
        blockedDomains: [String]? = nil,
        userLocation: UserLocation? = nil
    ) {
        self.maxUses = maxUses
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.userLocation = userLocation
    }

}

public let anthropicWebSearch20250305ArgsSchema = FlexibleSchema(
    Schema<AnthropicWebSearchToolArgs>.codable(
        AnthropicWebSearchToolArgs.self,
        jsonSchema: .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "maxUses": .object(["type": .string("number")]),
                "allowedDomains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
                "blockedDomains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")]),
                ]),
                "userLocation": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "required": .array([.string("type")]),
                    "properties": .object([
                        "type": .object(["const": .string("approximate")]),
                        "city": .object(["type": .string("string")]),
                        "region": .object(["type": .string("string")]),
                        "country": .object(["type": .string("string")]),
                        "timezone": .object(["type": .string("string")]),
                    ]),
                ]),
            ]),
        ])
    )
)

public let anthropicWebSearch20250305OutputSchema = FlexibleSchema(
    Schema<[AnthropicWebSearchToolResult]>.codable(
        [AnthropicWebSearchToolResult].self,
        jsonSchema: .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "required": .array([
                    .string("url"),
                    .string("title"),
                    .string("pageAge"),
                    .string("encryptedContent"),
                    .string("type"),
                ]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "url": .object(["type": .string("string")]),
                    "title": .object(["type": .array([.string("string"), .string("null")])]),
                    "pageAge": .object(["type": .array([.string("string"), .string("null")])]),
                    "encryptedContent": .object(["type": .string("string")]),
                    "type": .object(["const": .string("web_search_result")]),
                ]),
            ]),
        ])
    )
)

private let anthropicWebSearch20250305ToolOutputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("object"),
                "required": .array([
                    .string("url"),
                    .string("title"),
                    .string("pageAge"),
                    .string("encryptedContent"),
                    .string("type"),
                ]),
                "additionalProperties": .bool(false),
                "properties": .object([
                    "url": .object(["type": .string("string")]),
                    "title": .object(["type": .array([.string("string"), .string("null")])]),
                    "pageAge": .object(["type": .array([.string("string"), .string("null")])]),
                    "encryptedContent": .object(["type": .string("string")]),
                    "type": .object(["const": .string("web_search_result")]),
                ]),
            ]),
        ])
    )
)

public struct AnthropicWebFetchOptions: Sendable, Equatable {
    public var maxUses: Int?
    public var allowedDomains: [String]?
    public var blockedDomains: [String]?
    public var citationsEnabled: Bool?
    public var maxContentTokens: Int?

    public init(
        maxUses: Int? = nil,
        allowedDomains: [String]? = nil,
        blockedDomains: [String]? = nil,
        citationsEnabled: Bool? = nil,
        maxContentTokens: Int? = nil
    ) {
        self.maxUses = maxUses
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.citationsEnabled = citationsEnabled
        self.maxContentTokens = maxContentTokens
    }
}

public struct AnthropicWebSearchOptions: Sendable, Equatable {
    public struct UserLocation: Sendable, Equatable {
        public var city: String?
        public var region: String?
        public var country: String?
        public var timezone: String?

        public init(city: String? = nil, region: String? = nil, country: String? = nil, timezone: String? = nil) {
            self.city = city
            self.region = region
            self.country = country
            self.timezone = timezone
        }
    }

    public var maxUses: Int?
    public var allowedDomains: [String]?
    public var blockedDomains: [String]?
    public var userLocation: UserLocation?

    public init(
        maxUses: Int? = nil,
        allowedDomains: [String]? = nil,
        blockedDomains: [String]? = nil,
        userLocation: UserLocation? = nil
    ) {
        self.maxUses = maxUses
        self.allowedDomains = allowedDomains
        self.blockedDomains = blockedDomains
        self.userLocation = userLocation
    }
}

private let anthropicWebFetchInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "required": .array([.string("url")]),
            "properties": .object([
                "url": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false)
        ])
    )
)

private let anthropicWebFetchFactory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.web_fetch_20250910",
    name: "web_fetch",
    inputSchema: anthropicWebFetchInputSchema,
    outputSchema: anthropicWebFetch20250910ToolOutputSchema
)

@discardableResult
public func anthropicWebFetch20250910(_ options: AnthropicWebFetchOptions = .init()) -> Tool {
    var args: [String: JSONValue] = [:]
    if let maxUses = options.maxUses {
        args["maxUses"] = .number(Double(maxUses))
    }
    if let allowed = options.allowedDomains {
        args["allowedDomains"] = .array(allowed.map(JSONValue.string))
    }
    if let blocked = options.blockedDomains {
        args["blockedDomains"] = .array(blocked.map(JSONValue.string))
    }
    if let citations = options.citationsEnabled {
        args["citations"] = .object(["enabled": .bool(citations)])
    }
    if let maxTokens = options.maxContentTokens {
        args["maxContentTokens"] = .number(Double(maxTokens))
    }
    return anthropicWebFetchFactory(ProviderToolFactoryWithOutputSchemaOptions(args: args))
}

private let anthropicWebSearchInputSchema = FlexibleSchema(
    jsonSchema(
        .object([
            "type": .string("object"),
            "required": .array([.string("query")]),
            "properties": .object([
                "query": .object(["type": .string("string")])
            ]),
            "additionalProperties": .bool(false)
        ])
    )
)

private let anthropicWebSearchFactory = createProviderToolFactoryWithOutputSchema(
    id: "anthropic.web_search_20250305",
    name: "web_search",
    inputSchema: anthropicWebSearchInputSchema,
    outputSchema: anthropicWebSearch20250305ToolOutputSchema
)

@discardableResult
public func anthropicWebSearch20250305(_ options: AnthropicWebSearchOptions = .init()) -> Tool {
    var args: [String: JSONValue] = [:]
    if let maxUses = options.maxUses {
        args["maxUses"] = .number(Double(maxUses))
    }
    if let allowed = options.allowedDomains {
        args["allowedDomains"] = .array(allowed.map(JSONValue.string))
    }
    if let blocked = options.blockedDomains {
        args["blockedDomains"] = .array(blocked.map(JSONValue.string))
    }
    if let location = options.userLocation {
        var locationObject: [String: JSONValue] = ["type": .string("approximate")]
        if let city = location.city { locationObject["city"] = .string(city) }
        if let region = location.region { locationObject["region"] = .string(region) }
        if let country = location.country { locationObject["country"] = .string(country) }
        if let timezone = location.timezone { locationObject["timezone"] = .string(timezone) }
        args["userLocation"] = .object(locationObject)
    }
    return anthropicWebSearchFactory(ProviderToolFactoryWithOutputSchemaOptions(args: args))
}

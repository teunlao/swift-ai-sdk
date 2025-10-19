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

            enum CodingKeys: String, CodingKey {
                case type
                case mediaType = "media_type"
                case data
            }
        }

        public let type: String
        public let title: String
        public let citations: Citations?
        public let source: Source
    }

    public let type: String
    public let url: String
    public let content: Content
    public let retrievedAt: String?

    enum CodingKeys: String, CodingKey {
        case type
        case url
        case content
        case retrievedAt = "retrieved_at"
    }
}

public struct AnthropicWebSearchToolResult: Codable, Equatable, Sendable {
    public let url: String
    public let title: String
    public let pageAge: String?
    public let encryptedContent: String
    public let type: String

    enum CodingKeys: String, CodingKey {
        case url
        case title
        case pageAge = "page_age"
        case encryptedContent = "encrypted_content"
        case type
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

    private enum CodingKeys: String, CodingKey {
        case maxUses = "max_uses"
        case allowedDomains = "allowed_domains"
        case blockedDomains = "blocked_domains"
        case citations
        case maxContentTokens = "max_content_tokens"
    }
}

public let anthropicWebFetch20250910ArgsSchema = FlexibleSchema(
    Schema<AnthropicWebFetchToolArgs>.codable(
        AnthropicWebFetchToolArgs.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

public let anthropicWebFetch20250910OutputSchema = FlexibleSchema(
    Schema<AnthropicWebFetchToolResult>.codable(
        AnthropicWebFetchToolResult.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

private let anthropicWebFetch20250910ToolOutputSchema = FlexibleSchema(
    jsonSchema(.object(["type": .string("object")]))
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

    private enum CodingKeys: String, CodingKey {
        case maxUses = "max_uses"
        case allowedDomains = "allowed_domains"
        case blockedDomains = "blocked_domains"
        case userLocation = "user_location"
    }
}

public let anthropicWebSearch20250305ArgsSchema = FlexibleSchema(
    Schema<AnthropicWebSearchToolArgs>.codable(
        AnthropicWebSearchToolArgs.self,
        jsonSchema: .object([
            "type": .string("object")
        ])
    )
)

public let anthropicWebSearch20250305OutputSchema = FlexibleSchema(
    Schema<[AnthropicWebSearchToolResult]>.codable(
        [AnthropicWebSearchToolResult].self,
        jsonSchema: .object(["type": .string("array")])
    )
)

private let anthropicWebSearch20250305ToolOutputSchema = FlexibleSchema(
    jsonSchema(.object(["type": .string("array")]))
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

private let anthropicWebFetchFactory = createProviderDefinedToolFactoryWithOutputSchema(
    id: "anthropic.web_fetch_20250910",
    name: "web_fetch",
    inputSchema: anthropicWebFetchInputSchema,
    outputSchema: anthropicWebFetch20250910ToolOutputSchema
)

@discardableResult
public func anthropicWebFetch20250910(_ options: AnthropicWebFetchOptions = .init()) -> Tool {
    var args: [String: JSONValue] = [:]
    if let maxUses = options.maxUses {
        args["max_uses"] = .number(Double(maxUses))
    }
    if let allowed = options.allowedDomains {
        args["allowed_domains"] = .array(allowed.map(JSONValue.string))
    }
    if let blocked = options.blockedDomains {
        args["blocked_domains"] = .array(blocked.map(JSONValue.string))
    }
    if let citations = options.citationsEnabled {
        args["citations"] = .object(["enabled": .bool(citations)])
    }
    if let maxTokens = options.maxContentTokens {
        args["max_content_tokens"] = .number(Double(maxTokens))
    }
    return anthropicWebFetchFactory(ProviderDefinedToolFactoryWithOutputSchemaOptions(args: args))
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

private let anthropicWebSearchFactory = createProviderDefinedToolFactoryWithOutputSchema(
    id: "anthropic.web_search_20250305",
    name: "web_search",
    inputSchema: anthropicWebSearchInputSchema,
    outputSchema: anthropicWebSearch20250305ToolOutputSchema
)

@discardableResult
public func anthropicWebSearch20250305(_ options: AnthropicWebSearchOptions = .init()) -> Tool {
    var args: [String: JSONValue] = [:]
    if let maxUses = options.maxUses {
        args["max_uses"] = .number(Double(maxUses))
    }
    if let allowed = options.allowedDomains {
        args["allowed_domains"] = .array(allowed.map(JSONValue.string))
    }
    if let blocked = options.blockedDomains {
        args["blocked_domains"] = .array(blocked.map(JSONValue.string))
    }
    if let location = options.userLocation {
        var locationObject: [String: JSONValue] = ["type": .string("approximate")]
        if let city = location.city { locationObject["city"] = .string(city) }
        if let region = location.region { locationObject["region"] = .string(region) }
        if let country = location.country { locationObject["country"] = .string(country) }
        if let timezone = location.timezone { locationObject["timezone"] = .string(timezone) }
        args["user_location"] = .object(locationObject)
    }
    return anthropicWebSearchFactory(ProviderDefinedToolFactoryWithOutputSchemaOptions(args: args))
}

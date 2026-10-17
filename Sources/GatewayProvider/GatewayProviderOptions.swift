import Foundation
import AISDKProvider

public struct GatewayProviderOptions: Sendable, Codable, Equatable {
    public enum Caching: String, Sendable, Codable { case auto }
    public enum ServiceTier: String, Sendable, Codable { case flex, priority }
    public enum Sort: String, Sendable, Codable { case cost, tps, ttft }

    public struct ProviderTimeouts: Sendable, Codable, Equatable {
        public let byok: [String: Double]?

        public init(byok: [String: Double]? = nil) {
            self.byok = byok
        }
    }

    public let only: [String]?
    public let order: [String]?
    public let user: String?
    public let tags: [String]?
    public let models: [String]?
    public let byok: [String: [[String: JSONValue]]]?
    public let caching: Caching?
    public let disallowPromptTraining: Bool?
    public let has: [String]?
    public let providerTimeouts: ProviderTimeouts?
    public let quotaEntityId: String?
    public let serviceTier: ServiceTier?
    public let sort: Sort?
    public let zeroDataRetention: Bool?
    public let additionalOptions: [String: JSONValue]

    public init(
        only: [String]? = nil,
        order: [String]? = nil,
        user: String? = nil,
        tags: [String]? = nil,
        models: [String]? = nil,
        byok: [String: [[String: JSONValue]]]? = nil,
        caching: Caching? = nil,
        disallowPromptTraining: Bool? = nil,
        has: [String]? = nil,
        providerTimeouts: ProviderTimeouts? = nil,
        quotaEntityId: String? = nil,
        serviceTier: ServiceTier? = nil,
        sort: Sort? = nil,
        zeroDataRetention: Bool? = nil,
        additionalOptions: [String: JSONValue] = [:]
    ) {
        self.only = only
        self.order = order
        self.user = user
        self.tags = tags
        self.models = models
        self.byok = byok
        self.caching = caching
        self.disallowPromptTraining = disallowPromptTraining
        self.has = has
        self.providerTimeouts = providerTimeouts
        self.quotaEntityId = quotaEntityId
        self.serviceTier = serviceTier
        self.sort = sort
        self.zeroDataRetention = zeroDataRetention
        self.additionalOptions = additionalOptions
    }

    private enum CodingKeys: String, CodingKey {
        case only, order, user, tags, models, byok, caching, disallowPromptTraining, has
        case providerTimeouts, quotaEntityId, serviceTier, sort, zeroDataRetention
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        only = try container.decodeIfPresent([String].self, forKey: .only)
        order = try container.decodeIfPresent([String].self, forKey: .order)
        user = try container.decodeIfPresent(String.self, forKey: .user)
        tags = try container.decodeIfPresent([String].self, forKey: .tags)
        models = try container.decodeIfPresent([String].self, forKey: .models)
        byok = try container.decodeIfPresent([String: [[String: JSONValue]]].self, forKey: .byok)
        caching = try container.decodeIfPresent(Caching.self, forKey: .caching)
        disallowPromptTraining = try container.decodeIfPresent(Bool.self, forKey: .disallowPromptTraining)
        has = try container.decodeIfPresent([String].self, forKey: .has)
        providerTimeouts = try container.decodeIfPresent(ProviderTimeouts.self, forKey: .providerTimeouts)
        quotaEntityId = try container.decodeIfPresent(String.self, forKey: .quotaEntityId)
        serviceTier = try container.decodeIfPresent(ServiceTier.self, forKey: .serviceTier)
        sort = try container.decodeIfPresent(Sort.self, forKey: .sort)
        zeroDataRetention = try container.decodeIfPresent(Bool.self, forKey: .zeroDataRetention)
        let extra = try decoder.container(keyedBy: GatewayCodingKey.self)
        additionalOptions = try extra.allKeys.reduce(into: [:]) { values, key in
            if CodingKeys(rawValue: key.stringValue) == nil {
                values[key.stringValue] = try extra.decode(JSONValue.self, forKey: key)
            }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var extra = encoder.container(keyedBy: GatewayCodingKey.self)
        for (key, value) in additionalOptions where CodingKeys(rawValue: key) == nil {
            try extra.encode(value, forKey: GatewayCodingKey(key))
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(only, forKey: .only)
        try container.encodeIfPresent(order, forKey: .order)
        try container.encodeIfPresent(user, forKey: .user)
        try container.encodeIfPresent(tags, forKey: .tags)
        try container.encodeIfPresent(models, forKey: .models)
        try container.encodeIfPresent(byok, forKey: .byok)
        try container.encodeIfPresent(caching, forKey: .caching)
        try container.encodeIfPresent(disallowPromptTraining, forKey: .disallowPromptTraining)
        try container.encodeIfPresent(has, forKey: .has)
        try container.encodeIfPresent(providerTimeouts, forKey: .providerTimeouts)
        try container.encodeIfPresent(quotaEntityId, forKey: .quotaEntityId)
        try container.encodeIfPresent(serviceTier, forKey: .serviceTier)
        try container.encodeIfPresent(sort, forKey: .sort)
        try container.encodeIfPresent(zeroDataRetention, forKey: .zeroDataRetention)
    }
}

struct GatewayCodingKey: CodingKey {
    let stringValue: String
    var intValue: Int? { nil }

    init(_ stringValue: String) { self.stringValue = stringValue }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

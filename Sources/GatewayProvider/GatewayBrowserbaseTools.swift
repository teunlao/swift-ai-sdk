import AISDKProvider

public struct GatewayBrowserbaseSearchConfig: Sendable, Equatable {
    public let numResults: Int?

    public init(numResults: Int? = nil) {
        self.numResults = numResults
    }

    var args: [String: JSONValue] {
        ["numResults": numResults.map { .number(Double($0)) }].compactMapValues { $0 }
    }
}

public struct GatewayBrowserbaseFetchConfig: Sendable, Equatable {
    public enum Format: String, Sendable { case raw, json, markdown }

    public let allowRedirects: Bool?
    public let allowInsecureSsl: Bool?
    public let proxies: Bool?
    public let format: Format?
    public let schema: [String: JSONValue]?

    public init(
        allowRedirects: Bool? = nil,
        allowInsecureSsl: Bool? = nil,
        proxies: Bool? = nil,
        format: Format? = nil,
        schema: [String: JSONValue]? = nil
    ) {
        self.allowRedirects = allowRedirects
        self.allowInsecureSsl = allowInsecureSsl
        self.proxies = proxies
        self.format = format
        self.schema = schema
    }

    var args: [String: JSONValue] {
        [
            "allowRedirects": allowRedirects.map(JSONValue.bool),
            "allowInsecureSsl": allowInsecureSsl.map(JSONValue.bool),
            "proxies": proxies.map(JSONValue.bool),
            "format": format.map { .string($0.rawValue) },
            "schema": schema.map(JSONValue.object),
        ].compactMapValues { $0 }
    }
}

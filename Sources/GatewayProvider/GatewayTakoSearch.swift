import AISDKProvider

public struct GatewayTakoSearchConfig: Sendable, Equatable {
    public enum Effort: String, Sendable { case deep, fast, instant }
    public enum ContentFormat: String, Sendable { case cardJSON = "card_json", csv, jsonCompact = "json_compact", jsonRecords = "json_records" }
    public enum Mode: String, Sendable { case inline, url }
    public enum WebCategory: String, Sendable { case finance, news, sports }

    public struct DataSource: Sendable, Equatable {
        public let count: Int?
        public let includeContents: Bool?
        public let mode: Mode?
        public let contentFormat: ContentFormat?
        public let maxRows: Int?
        public let nodeIds: [String]?
        public let strict: Bool?

        public init(
            count: Int? = nil, includeContents: Bool? = nil, mode: Mode? = nil,
            contentFormat: ContentFormat? = nil, maxRows: Int? = nil, nodeIds: [String]? = nil, strict: Bool? = nil
        ) {
            self.count = count
            self.includeContents = includeContents
            self.mode = mode
            self.contentFormat = contentFormat
            self.maxRows = maxRows
            self.nodeIds = nodeIds
            self.strict = strict
        }

        var json: JSONValue {
            .object([
                "count": count.map { .number(Double($0)) },
                "includeContents": includeContents.map(JSONValue.bool),
                "mode": mode.map { .string($0.rawValue) },
                "contentFormat": contentFormat.map { .string($0.rawValue) },
                "maxRows": maxRows.map { .number(Double($0)) },
                "nodeIds": nodeIds.map { .array($0.map(JSONValue.string)) },
                "strict": strict.map(JSONValue.bool),
            ].compactMapValues { $0 })
        }
    }

    public struct WebSource: Sendable, Equatable {
        public let count: Int?
        public let includeContents: Bool?
        public let category: WebCategory?
        public let includeDomains: [String]?
        public let excludeDomains: [String]?
        public let snippetMaxChars: Int?
        public let highlights: Bool?
        public let articleContentMaxChars: Int?
        public let publishedAfter: String?
        public let publishedBefore: String?

        public init(
            count: Int? = nil, includeContents: Bool? = nil, category: WebCategory? = nil,
            includeDomains: [String]? = nil, excludeDomains: [String]? = nil, snippetMaxChars: Int? = nil,
            highlights: Bool? = nil, articleContentMaxChars: Int? = nil,
            publishedAfter: String? = nil, publishedBefore: String? = nil
        ) {
            self.count = count
            self.includeContents = includeContents
            self.category = category
            self.includeDomains = includeDomains
            self.excludeDomains = excludeDomains
            self.snippetMaxChars = snippetMaxChars
            self.highlights = highlights
            self.articleContentMaxChars = articleContentMaxChars
            self.publishedAfter = publishedAfter
            self.publishedBefore = publishedBefore
        }

        var json: JSONValue {
            .object([
                "count": count.map { .number(Double($0)) },
                "includeContents": includeContents.map(JSONValue.bool),
                "category": category.map { .string($0.rawValue) },
                "includeDomains": includeDomains.map { .array($0.map(JSONValue.string)) },
                "excludeDomains": excludeDomains.map { .array($0.map(JSONValue.string)) },
                "snippetMaxChars": snippetMaxChars.map { .number(Double($0)) },
                "highlights": highlights.map(JSONValue.bool),
                "articleContentMaxChars": articleContentMaxChars.map { .number(Double($0)) },
                "publishedAfter": publishedAfter.map(JSONValue.string),
                "publishedBefore": publishedBefore.map(JSONValue.string),
            ].compactMapValues { $0 })
        }
    }

    public struct Sources: Sendable, Equatable {
        public let data: DataSource?
        public let web: WebSource?

        public init(data: DataSource? = nil, web: WebSource? = nil) {
            self.data = data
            self.web = web
        }

        var json: JSONValue {
            .object(["data": data?.json, "web": web?.json].compactMapValues { $0 })
        }
    }

    public struct Location: Sendable, Equatable {
        public let latitude: Double
        public let longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    public struct OutputSettings: Sendable, Equatable {
        public let imageDarkMode: Bool?
        public let forceRefresh: Bool?

        public init(imageDarkMode: Bool? = nil, forceRefresh: Bool? = nil) {
            self.imageDarkMode = imageDarkMode
            self.forceRefresh = forceRefresh
        }

        var json: JSONValue {
            .object([
                "imageDarkMode": imageDarkMode.map(JSONValue.bool),
                "forceRefresh": forceRefresh.map(JSONValue.bool),
            ].compactMapValues { $0 })
        }
    }

    public let effort: Effort?
    public let sources: Sources?
    public let location: Location?
    public let countryCode: String?
    public let locale: String?
    public let timezone: String?
    public let outputSettings: OutputSettings?
    public let includeRelated: Int?

    public init(
        effort: Effort? = nil, sources: Sources? = nil, location: Location? = nil,
        countryCode: String? = nil, locale: String? = nil, timezone: String? = nil,
        outputSettings: OutputSettings? = nil, includeRelated: Int? = nil
    ) {
        self.effort = effort
        self.sources = sources
        self.location = location
        self.countryCode = countryCode
        self.locale = locale
        self.timezone = timezone
        self.outputSettings = outputSettings
        self.includeRelated = includeRelated
    }

    var args: [String: JSONValue] {
        [
            "effort": effort.map { .string($0.rawValue) },
            "sources": sources?.json,
            "location": location.map { .object(["latitude": .number($0.latitude), "longitude": .number($0.longitude)]) },
            "countryCode": countryCode.map(JSONValue.string),
            "locale": locale.map(JSONValue.string),
            "timezone": timezone.map(JSONValue.string),
            "outputSettings": outputSettings?.json,
            "includeRelated": includeRelated.map { .number(Double($0)) },
        ].compactMapValues { $0 }
    }
}

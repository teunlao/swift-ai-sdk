import AISDKProvider

public struct GatewayExaSearchConfig: Sendable, Equatable {
    public enum SearchType: String, Sendable { case auto, fast, instant }
    public enum Category: String, Sendable {
        case company, people, researchPaper = "research paper", news, personalSite = "personal site", financialReport = "financial report"
    }
    public enum TextSection: String, Sendable { case header, navigation, banner, body, sidebar, footer, metadata }
    public enum Verbosity: String, Sendable { case compact, standard, full }

    public struct Text: Sendable, Equatable {
        public let maxCharacters: Int?
        public let includeHtmlTags: Bool?
        public let verbosity: Verbosity?
        public let includeSections: [TextSection]?
        public let excludeSections: [TextSection]?

        public init(
            maxCharacters: Int? = nil, includeHtmlTags: Bool? = nil, verbosity: Verbosity? = nil,
            includeSections: [TextSection]? = nil, excludeSections: [TextSection]? = nil
        ) {
            self.maxCharacters = maxCharacters
            self.includeHtmlTags = includeHtmlTags
            self.verbosity = verbosity
            self.includeSections = includeSections
            self.excludeSections = excludeSections
        }

        var json: JSONValue {
            .object([
                "maxCharacters": maxCharacters.map { .number(Double($0)) },
                "includeHtmlTags": includeHtmlTags.map(JSONValue.bool),
                "verbosity": verbosity.map { .string($0.rawValue) },
                "includeSections": includeSections.map { .array($0.map { .string($0.rawValue) }) },
                "excludeSections": excludeSections.map { .array($0.map { .string($0.rawValue) }) },
            ].compactMapValues { $0 })
        }
    }

    public struct Highlights: Sendable, Equatable {
        public let query: String?
        public let maxCharacters: Int?

        public init(query: String? = nil, maxCharacters: Int? = nil) {
            self.query = query
            self.maxCharacters = maxCharacters
        }

        var json: JSONValue {
            .object([
                "query": query.map(JSONValue.string),
                "maxCharacters": maxCharacters.map { .number(Double($0)) },
            ].compactMapValues { $0 })
        }
    }

    public struct Extras: Sendable, Equatable {
        public let links: Int?
        public let imageLinks: Int?

        public init(links: Int? = nil, imageLinks: Int? = nil) {
            self.links = links
            self.imageLinks = imageLinks
        }

        var json: JSONValue {
            .object([
                "links": links.map { .number(Double($0)) },
                "imageLinks": imageLinks.map { .number(Double($0)) },
            ].compactMapValues { $0 })
        }
    }

    public enum TextOption: Sendable, Equatable { case enabled(Bool), options(Text) }
    public enum HighlightsOption: Sendable, Equatable { case enabled(Bool), options(Highlights) }
    public enum SubpageTarget: Sendable, Equatable { case single(String), multiple([String]) }

    public struct Contents: Sendable, Equatable {
        public let text: TextOption?
        public let highlights: HighlightsOption?
        public let maxAgeHours: Double?
        public let livecrawlTimeout: Double?
        public let subpages: Int?
        public let subpageTarget: SubpageTarget?
        public let extras: Extras?

        public init(
            text: TextOption? = nil, highlights: HighlightsOption? = nil, maxAgeHours: Double? = nil,
            livecrawlTimeout: Double? = nil, subpages: Int? = nil, subpageTarget: SubpageTarget? = nil, extras: Extras? = nil
        ) {
            self.text = text
            self.highlights = highlights
            self.maxAgeHours = maxAgeHours
            self.livecrawlTimeout = livecrawlTimeout
            self.subpages = subpages
            self.subpageTarget = subpageTarget
            self.extras = extras
        }

        var json: JSONValue {
            var values: [String: JSONValue] = [
                "maxAgeHours": maxAgeHours.map(JSONValue.number),
                "livecrawlTimeout": livecrawlTimeout.map(JSONValue.number),
                "subpages": subpages.map { .number(Double($0)) },
                "extras": extras?.json,
            ].compactMapValues { $0 }
            if let text {
                switch text {
                case .enabled(let value): values["text"] = .bool(value)
                case .options(let value): values["text"] = value.json
                }
            }
            if let highlights {
                switch highlights {
                case .enabled(let value): values["highlights"] = .bool(value)
                case .options(let value): values["highlights"] = value.json
                }
            }
            if let subpageTarget {
                switch subpageTarget {
                case .single(let value): values["subpageTarget"] = .string(value)
                case .multiple(let value): values["subpageTarget"] = .array(value.map(JSONValue.string))
                }
            }
            return .object(values)
        }
    }

    public let type: SearchType?
    public let numResults: Int?
    public let category: Category?
    public let userLocation: String?
    public let includeDomains: [String]?
    public let excludeDomains: [String]?
    public let startPublishedDate: String?
    public let endPublishedDate: String?
    public let contents: Contents?

    public init(
        type: SearchType? = nil, numResults: Int? = nil, category: Category? = nil, userLocation: String? = nil,
        includeDomains: [String]? = nil, excludeDomains: [String]? = nil,
        startPublishedDate: String? = nil, endPublishedDate: String? = nil, contents: Contents? = nil
    ) {
        self.type = type
        self.numResults = numResults
        self.category = category
        self.userLocation = userLocation
        self.includeDomains = includeDomains
        self.excludeDomains = excludeDomains
        self.startPublishedDate = startPublishedDate
        self.endPublishedDate = endPublishedDate
        self.contents = contents
    }

    var args: [String: JSONValue] {
        [
            "type": type.map { .string($0.rawValue) },
            "numResults": numResults.map { .number(Double($0)) },
            "category": category.map { .string($0.rawValue) },
            "userLocation": userLocation.map(JSONValue.string),
            "includeDomains": includeDomains.map { .array($0.map(JSONValue.string)) },
            "excludeDomains": excludeDomains.map { .array($0.map(JSONValue.string)) },
            "startPublishedDate": startPublishedDate.map(JSONValue.string),
            "endPublishedDate": endPublishedDate.map(JSONValue.string),
            "contents": contents?.json,
        ].compactMapValues { $0 }
    }
}

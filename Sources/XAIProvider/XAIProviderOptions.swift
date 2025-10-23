import Foundation
import AISDKProvider
import AISDKProviderUtils

/// xAI-specific provider options.
/// Mirrors `packages/xai/src/xai-chat-options.ts`.
public struct XAIProviderOptions: Sendable, Equatable {
    public var reasoningEffort: XAIReasoningEffort?
    public var searchParameters: XAISearchParameters?

    public init(reasoningEffort: XAIReasoningEffort? = nil, searchParameters: XAISearchParameters? = nil) {
        self.reasoningEffort = reasoningEffort
        self.searchParameters = searchParameters
    }
}

public enum XAIReasoningEffort: String, Sendable, Equatable {
    case low
    case high
}

public struct XAISearchParameters: Sendable, Equatable {
    public var mode: XAISearchMode
    public var returnCitations: Bool?
    public var fromDate: String?
    public var toDate: String?
    public var maxSearchResults: Int?
    public var sources: [XAISearchSource]?

    public init(
        mode: XAISearchMode,
        returnCitations: Bool? = nil,
        fromDate: String? = nil,
        toDate: String? = nil,
        maxSearchResults: Int? = nil,
        sources: [XAISearchSource]? = nil
    ) {
        self.mode = mode
        self.returnCitations = returnCitations
        self.fromDate = fromDate
        self.toDate = toDate
        self.maxSearchResults = maxSearchResults
        self.sources = sources
    }

    func toJSONValue() -> JSONValue {
        var object: [String: JSONValue] = [
            "mode": .string(mode.rawValue)
        ]
        if let returnCitations {
            object["return_citations"] = .bool(returnCitations)
        }
        if let fromDate {
            object["from_date"] = .string(fromDate)
        }
        if let toDate {
            object["to_date"] = .string(toDate)
        }
        if let maxSearchResults {
            object["max_search_results"] = .number(Double(maxSearchResults))
        }
        if let sources, !sources.isEmpty {
            object["sources"] = .array(sources.map { $0.toJSONValue() })
        }
        return .object(object)
    }
}

public enum XAISearchMode: String, Sendable, Equatable {
    case off
    case auto
    case on
}

public enum XAISearchSource: Sendable, Equatable {
    case web(WebSource)
    case x(XSource)
    case news(NewsSource)
    case rss(RSSSource)

    public struct WebSource: Sendable, Equatable {
        public var country: String?
        public var excludedWebsites: [String]?
        public var allowedWebsites: [String]?
        public var safeSearch: Bool?
    }

    public struct XSource: Sendable, Equatable {
        public var excludedXHandles: [String]?
        public var includedXHandles: [String]?
        public var legacyHandles: [String]?
        public var postFavoriteCount: Int?
        public var postViewCount: Int?
    }

    public struct NewsSource: Sendable, Equatable {
        public var country: String?
        public var excludedWebsites: [String]?
        public var safeSearch: Bool?
    }

    public struct RSSSource: Sendable, Equatable {
        public var links: [String]
    }

    func toJSONValue() -> JSONValue {
        switch self {
        case .web(let source):
            var payload: [String: JSONValue] = ["type": .string("web")]
            if let country = source.country {
                payload["country"] = .string(country)
            }
            if let excluded = source.excludedWebsites, !excluded.isEmpty {
                payload["excluded_websites"] = .array(excluded.map(JSONValue.string))
            }
            if let allowed = source.allowedWebsites, !allowed.isEmpty {
                payload["allowed_websites"] = .array(allowed.map(JSONValue.string))
            }
            if let safe = source.safeSearch {
                payload["safe_search"] = .bool(safe)
            }
            return .object(payload)
        case .x(let source):
            var payload: [String: JSONValue] = ["type": .string("x")]
            if let excluded = source.excludedXHandles, !excluded.isEmpty {
                payload["excluded_x_handles"] = .array(excluded.map(JSONValue.string))
            }
            let includedHandles = source.includedXHandles ?? source.legacyHandles
            if let included = includedHandles, !included.isEmpty {
                payload["included_x_handles"] = .array(included.map(JSONValue.string))
            }
            if let favoriteCount = source.postFavoriteCount {
                payload["post_favorite_count"] = .number(Double(favoriteCount))
            }
            if let viewCount = source.postViewCount {
                payload["post_view_count"] = .number(Double(viewCount))
            }
            return .object(payload)
        case .news(let source):
            var payload: [String: JSONValue] = ["type": .string("news")]
            if let country = source.country {
                payload["country"] = .string(country)
            }
            if let excluded = source.excludedWebsites, !excluded.isEmpty {
                payload["excluded_websites"] = .array(excluded.map(JSONValue.string))
            }
            if let safe = source.safeSearch {
                payload["safe_search"] = .bool(safe)
            }
            return .object(payload)
        case .rss(let source):
            return .object([
                "type": .string("rss"),
                "links": .array(source.links.map(JSONValue.string))
            ])
        }
    }
}

private let xaiProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let xaiProviderOptionsSchema = FlexibleSchema(
    Schema<XAIProviderOptions>(
        jsonSchemaResolver: { xaiProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "xai",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var reasoningEffort: XAIReasoningEffort? = nil
                if let effortValue = dict["reasoningEffort"], effortValue != .null {
                    guard case .string(let raw) = effortValue,
                          let parsed = XAIReasoningEffort(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "reasoningEffort must be 'low' or 'high'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: effortValue, cause: error))
                    }
                    reasoningEffort = parsed
                }

                var searchParameters: XAISearchParameters? = nil
                if let searchValue = dict["searchParameters"], searchValue != .null {
                    guard case .object(let searchDict) = searchValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "searchParameters must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: searchValue, cause: error))
                    }

                    guard let modeValue = searchDict["mode"], case .string(let modeRaw) = modeValue,
                          let mode = XAISearchMode(rawValue: modeRaw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "xai",
                            issues: "searchParameters.mode must be 'off', 'auto', or 'on'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: searchDict["mode"] ?? .null, cause: error))
                    }

                    var params = XAISearchParameters(mode: mode)

                    if let returnCitationsValue = searchDict["returnCitations"], returnCitationsValue != .null {
                        guard case .bool(let bool) = returnCitationsValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "searchParameters.returnCitations must be a boolean"
                            )
                            return .failure(error: TypeValidationError.wrap(value: returnCitationsValue, cause: error))
                        }
                        params.returnCitations = bool
                    }

                    if let fromDateValue = searchDict["fromDate"], fromDateValue != .null {
                        guard case .string(let string) = fromDateValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "searchParameters.fromDate must be a string"
                            )
                            return .failure(error: TypeValidationError.wrap(value: fromDateValue, cause: error))
                        }
                        params.fromDate = string
                    }

                    if let toDateValue = searchDict["toDate"], toDateValue != .null {
                        guard case .string(let string) = toDateValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "searchParameters.toDate must be a string"
                            )
                            return .failure(error: TypeValidationError.wrap(value: toDateValue, cause: error))
                        }
                        params.toDate = string
                    }

                    if let maxResultsValue = searchDict["maxSearchResults"], maxResultsValue != .null {
                        guard case .number(let number) = maxResultsValue,
                              let intValue = Int(exactly: number) else {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "searchParameters.maxSearchResults must be an integer"
                            )
                            return .failure(error: TypeValidationError.wrap(value: maxResultsValue, cause: error))
                        }
                        if intValue < 1 || intValue > 50 {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "searchParameters.maxSearchResults must be between 1 and 50"
                            )
                            return .failure(error: TypeValidationError.wrap(value: maxResultsValue, cause: error))
                        }
                        params.maxSearchResults = intValue
                    }

                    if let sourcesValue = searchDict["sources"], sourcesValue != .null {
                        guard case .array(let sourcesArray) = sourcesValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: "xai",
                                issues: "searchParameters.sources must be an array"
                            )
                            return .failure(error: TypeValidationError.wrap(value: sourcesValue, cause: error))
                        }

                        var parsedSources: [XAISearchSource] = []
                        parsedSources.reserveCapacity(sourcesArray.count)

                        for entry in sourcesArray {
                            guard case .object(let sourceDict) = entry else {
                                let error = SchemaValidationIssuesError(
                                    vendor: "xai",
                                    issues: "each source must be an object"
                                )
                                return .failure(error: TypeValidationError.wrap(value: entry, cause: error))
                            }

                            guard let typeValue = sourceDict["type"], case .string(let typeRaw) = typeValue else {
                                let error = SchemaValidationIssuesError(
                                    vendor: "xai",
                                    issues: "source.type must be a string"
                                )
                                return .failure(error: TypeValidationError.wrap(value: sourceDict["type"] ?? .null, cause: error))
                            }

                            switch typeRaw {
                            case "web":
                                var webSource = XAISearchSource.WebSource()
                                if let countryValue = sourceDict["country"], countryValue != .null {
                                    guard case .string(let country) = countryValue else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "web country must be a string"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: countryValue, cause: error))
                                    }
                                    guard country.count == 2 else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "web country must be a 2-letter ISO code"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: countryValue, cause: error))
                                    }
                                    webSource.country = country.uppercased()
                                }
                                if let excludedValue = sourceDict["excludedWebsites"], excludedValue != .null {
                                    guard let list = parseStringArray(excludedValue, maxCount: 5) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "web excludedWebsites must be an array of up to 5 strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: excludedValue, cause: error))
                                    }
                                    webSource.excludedWebsites = list
                                }
                                if let allowedValue = sourceDict["allowedWebsites"], allowedValue != .null {
                                    guard let list = parseStringArray(allowedValue, maxCount: 5) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "web allowedWebsites must be an array of up to 5 strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: allowedValue, cause: error))
                                    }
                                    webSource.allowedWebsites = list
                                }
                                if let safeValue = sourceDict["safeSearch"], safeValue != .null {
                                    guard case .bool(let bool) = safeValue else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "web safeSearch must be a boolean"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: safeValue, cause: error))
                                    }
                                    webSource.safeSearch = bool
                                }
                                parsedSources.append(.web(webSource))

                            case "x":
                                var xSource = XAISearchSource.XSource()
                                if let excludedValue = sourceDict["excludedXHandles"], excludedValue != .null {
                                    guard let list = parseStringArray(excludedValue) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "x excludedXHandles must be an array of strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: excludedValue, cause: error))
                                    }
                                    xSource.excludedXHandles = list
                                }
                                if let includedValue = sourceDict["includedXHandles"], includedValue != .null {
                                    guard let list = parseStringArray(includedValue) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "x includedXHandles must be an array of strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: includedValue, cause: error))
                                    }
                                    xSource.includedXHandles = list
                                }
                                if let legacyValue = sourceDict["xHandles"], legacyValue != .null {
                                    guard let list = parseStringArray(legacyValue) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "x xHandles must be an array of strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: legacyValue, cause: error))
                                    }
                                    xSource.legacyHandles = list
                                }
                                if let favoriteValue = sourceDict["postFavoriteCount"], favoriteValue != .null {
                                    guard let intValue = parseInteger(favoriteValue) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "x postFavoriteCount must be an integer"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: favoriteValue, cause: error))
                                    }
                                    xSource.postFavoriteCount = intValue
                                }
                                if let viewValue = sourceDict["postViewCount"], viewValue != .null {
                                    guard let intValue = parseInteger(viewValue) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "x postViewCount must be an integer"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: viewValue, cause: error))
                                    }
                                    xSource.postViewCount = intValue
                                }
                                parsedSources.append(.x(xSource))

                            case "news":
                                var newsSource = XAISearchSource.NewsSource()
                                if let countryValue = sourceDict["country"], countryValue != .null {
                                    guard case .string(let country) = countryValue else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "news country must be a string"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: countryValue, cause: error))
                                    }
                                    guard country.count == 2 else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "news country must be a 2-letter ISO code"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: countryValue, cause: error))
                                    }
                                    newsSource.country = country.uppercased()
                                }
                                if let excludedValue = sourceDict["excludedWebsites"], excludedValue != .null {
                                    guard let list = parseStringArray(excludedValue, maxCount: 5) else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "news excludedWebsites must be an array of up to 5 strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: excludedValue, cause: error))
                                    }
                                    newsSource.excludedWebsites = list
                                }
                                if let safeValue = sourceDict["safeSearch"], safeValue != .null {
                                    guard case .bool(let bool) = safeValue else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "news safeSearch must be a boolean"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: safeValue, cause: error))
                                    }
                                    newsSource.safeSearch = bool
                                }
                                parsedSources.append(.news(newsSource))

                            case "rss":
                                guard let linksValue = sourceDict["links"], case .array(let linksArray) = linksValue else {
                                    let error = SchemaValidationIssuesError(
                                        vendor: "xai",
                                        issues: "rss links must be an array"
                                    )
                                    return .failure(error: TypeValidationError.wrap(value: sourceDict["links"] ?? .null, cause: error))
                                }
                                if linksArray.count > 1 {
                                    let error = SchemaValidationIssuesError(
                                        vendor: "xai",
                                        issues: "rss links currently supports at most one entry"
                                    )
                                    return .failure(error: TypeValidationError.wrap(value: linksValue, cause: error))
                                }
                                var links: [String] = []
                                for entry in linksArray {
                                    guard case .string(let link) = entry else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "rss links must be strings"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: entry, cause: error))
                                    }
                                    guard let url = URL(string: link), url.scheme != nil else {
                                        let error = SchemaValidationIssuesError(
                                            vendor: "xai",
                                            issues: "rss links must be valid URLs"
                                        )
                                        return .failure(error: TypeValidationError.wrap(value: entry, cause: error))
                                    }
                                    links.append(link)
                                }
                                parsedSources.append(.rss(XAISearchSource.RSSSource(links: links)))

                            default:
                                let error = SchemaValidationIssuesError(
                                    vendor: "xai",
                                    issues: "unsupported source type \(typeRaw)"
                                )
                                return .failure(error: TypeValidationError.wrap(value: entry, cause: error))
                            }
                        }

                        params.sources = parsedSources
                    }

                    searchParameters = params
                }

                return .success(value: XAIProviderOptions(reasoningEffort: reasoningEffort, searchParameters: searchParameters))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

private func parseStringArray(_ value: JSONValue, maxCount: Int? = nil) -> [String]? {
    guard case .array(let array) = value else { return nil }
    if let maxCount, array.count > maxCount { return nil }
    var result: [String] = []
    result.reserveCapacity(array.count)
    for entry in array {
        guard case .string(let string) = entry else { return nil }
        result.append(string)
    }
    return result
}

private func parseInteger(_ value: JSONValue) -> Int? {
    guard case .number(let number) = value, number.isFinite else { return nil }
    let rounded = number.rounded(.towardZero)
    guard rounded == number else { return nil }
    if rounded < Double(Int.min) || rounded > Double(Int.max) { return nil }
    return Int(rounded)
}

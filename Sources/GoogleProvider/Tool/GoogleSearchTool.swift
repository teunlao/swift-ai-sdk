import AISDKProvider
import AISDKProviderUtils

public struct GoogleSearchArgs: Sendable, Equatable {
    public struct SearchTypes: Sendable, Equatable {
        public var webSearch: Bool
        public var imageSearch: Bool
        public init(webSearch: Bool = false, imageSearch: Bool = false) { self.webSearch = webSearch; self.imageSearch = imageSearch }
    }
    public struct TimeRangeFilter: Sendable, Equatable {
        public var startTime: String
        public var endTime: String
        public init(startTime: String, endTime: String) { self.startTime = startTime; self.endTime = endTime }
    }
    public var searchTypes: SearchTypes?
    public var timeRangeFilter: TimeRangeFilter?
    public var additional: [String: JSONValue]
    public init(searchTypes: SearchTypes? = nil, timeRangeFilter: TimeRangeFilter? = nil, additional: [String: JSONValue] = [:]) {
        self.searchTypes = searchTypes; self.timeRangeFilter = timeRangeFilter; self.additional = additional
    }
}

private let googleSearchSchema = FlexibleSchema(jsonSchema(.object(["type": .string("object"), "properties": .object([:]), "additionalProperties": .bool(false)])))
public let googleSearchToolFactory = createProviderExecutedToolFactory(
    id: "google.google_search",
    name: "google_search",
    inputSchema: googleSearchSchema,
    outputSchema: googleSearchSchema,
    mapOptions: { (args: GoogleSearchArgs) in ProviderExecutedToolFactoryOptions(args: args.toDictionary()) }
)

public extension GoogleSearchArgs {
    func toDictionary() -> JSONObject {
        var values = additional
        if let types = searchTypes {
            var object: JSONObject = [:]
            if types.webSearch { object["webSearch"] = .object([:]) }
            if types.imageSearch { object["imageSearch"] = .object([:]) }
            values["searchTypes"] = .object(object)
        }
        if let range = timeRangeFilter { values["timeRangeFilter"] = .object(["startTime": .string(range.startTime), "endTime": .string(range.endTime)]) }
        return values
    }
}

@discardableResult
public func googleSearchTool(_ args: GoogleSearchArgs = .init()) -> Tool { googleSearchToolFactory(args) }

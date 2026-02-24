import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIWebSearchArgs: Sendable, Equatable {
    public struct Filters: Sendable, Equatable {
        public let allowedDomains: [String]?

        public init(allowedDomains: [String]? = nil) {
            self.allowedDomains = allowedDomains
        }
    }

    public struct UserLocation: Sendable, Equatable {
        public enum LocationType: String, Sendable, Equatable, Codable {
            case approximate
        }

        public let type: LocationType
        public let country: String?
        public let city: String?
        public let region: String?
        public let timezone: String?

        public init(
            type: LocationType = .approximate,
            country: String? = nil,
            city: String? = nil,
            region: String? = nil,
            timezone: String? = nil
        ) {
            self.type = type
            self.country = country
            self.city = city
            self.region = region
            self.timezone = timezone
        }
    }

    public let filters: Filters?
    public let externalWebAccess: Bool?
    public let searchContextSize: String?
    public let userLocation: UserLocation?

    public init(
        filters: Filters? = nil,
        externalWebAccess: Bool? = nil,
        searchContextSize: String? = nil,
        userLocation: UserLocation? = nil
    ) {
        self.filters = filters
        self.externalWebAccess = externalWebAccess
        self.searchContextSize = searchContextSize
        self.userLocation = userLocation
    }
}

private let webSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "externalWebAccess": .object([
            "type": .string("boolean")
        ]),
        "filters": .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "allowedDomains": .object([
                    "type": .string("array"),
                    "items": .object(["type": .string("string")])
                ])
            ])
        ]),
        "searchContextSize": .object([
            "type": .string("string"),
            "enum": .array([.string("low"), .string("medium"), .string("high")])
        ]),
        "userLocation": .object([
            "type": .string("object"),
            "required": .array([.string("type")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object([
                    "type": .string("string"),
                    "enum": .array([.string("approximate")])
                ]),
                "country": .object([
                    "type": .string("string")
                ]),
                "city": .object([
                    "type": .string("string")
                ]),
                "region": .object([
                    "type": .string("string")
                ]),
                "timezone": .object([
                    "type": .string("string")
                ])
            ])
        ])
    ])
])

public let openaiWebSearchArgsSchema = FlexibleSchema<OpenAIWebSearchArgs>(
    Schema(
        jsonSchemaResolver: { webSearchArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var filters: OpenAIWebSearchArgs.Filters? = nil
                if let filtersValue = dict["filters"] {
                    if filtersValue == .null {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters must be an object")
                        return .failure(error: TypeValidationError.wrap(value: filtersValue, cause: error))
                    }
                    guard case .object(let filtersObject) = filtersValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters must be an object")
                        return .failure(error: TypeValidationError.wrap(value: filtersValue, cause: error))
                    }
                    if let domainsValue = filtersObject["allowedDomains"] {
                        if domainsValue == .null {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters.allowedDomains must be an array")
                            return .failure(error: TypeValidationError.wrap(value: domainsValue, cause: error))
                        }
                        guard case .array(let array) = domainsValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters.allowedDomains must be an array")
                            return .failure(error: TypeValidationError.wrap(value: domainsValue, cause: error))
                        }
                        let domains = try array.map { element -> String in
                            guard case .string(let domain) = element else {
                                let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedDomains must contain strings")
                                throw TypeValidationError.wrap(value: element, cause: error)
                            }
                            return domain
                        }
                        filters = OpenAIWebSearchArgs.Filters(allowedDomains: domains)
                    } else {
                        filters = OpenAIWebSearchArgs.Filters()
                    }
                }

                var externalWebAccess: Bool? = nil
                if let externalWebAccessValue = dict["externalWebAccess"] {
                    if externalWebAccessValue == .null {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "externalWebAccess must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: externalWebAccessValue, cause: error))
                    }
                    guard case .bool(let bool) = externalWebAccessValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "externalWebAccess must be a boolean")
                        return .failure(error: TypeValidationError.wrap(value: externalWebAccessValue, cause: error))
                    }
                    externalWebAccess = bool
                }

                var searchContextSize: String? = nil
                if let sizeValue = dict["searchContextSize"] {
                    if sizeValue == .null {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "searchContextSize must be 'low', 'medium', or 'high'")
                        return .failure(error: TypeValidationError.wrap(value: sizeValue, cause: error))
                    }
                    guard case .string(let size) = sizeValue,
                          ["low", "medium", "high"].contains(size) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "searchContextSize must be 'low', 'medium', or 'high'")
                        return .failure(error: TypeValidationError.wrap(value: sizeValue, cause: error))
                    }
                    searchContextSize = size
                }

                var userLocation: OpenAIWebSearchArgs.UserLocation? = nil
                if let locationValue = dict["userLocation"] {
                    if locationValue == .null {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation must be an object")
                        return .failure(error: TypeValidationError.wrap(value: locationValue, cause: error))
                    }
                    guard case .object(let locationObject) = locationValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation must be an object")
                        return .failure(error: TypeValidationError.wrap(value: locationValue, cause: error))
                    }
                    guard let typeValue = locationObject["type"] else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation.type must be 'approximate'")
                        return .failure(error: TypeValidationError.wrap(value: locationValue, cause: error))
                    }
                    guard case .string(let typeString) = typeValue, typeString == "approximate" else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation.type must be 'approximate'")
                        return .failure(error: TypeValidationError.wrap(value: typeValue, cause: error))
                    }
                    func optionalString(_ key: String) throws -> String? {
                        guard let value = locationObject[key] else { return nil }
                        guard case .string(let string) = value else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation.\(key) must be a string")
                            throw TypeValidationError.wrap(value: value, cause: error)
                        }
                        return string
                    }
                    userLocation = OpenAIWebSearchArgs.UserLocation(
                        type: .approximate,
                        country: try optionalString("country"),
                        city: try optionalString("city"),
                        region: try optionalString("region"),
                        timezone: try optionalString("timezone")
                    )
                }

                let args = OpenAIWebSearchArgs(
                    filters: filters,
                    externalWebAccess: externalWebAccess,
                    searchContextSize: searchContextSize,
                    userLocation: userLocation
                )

                return .success(value: args)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                let wrapped = TypeValidationError.wrap(value: value, cause: error)
                return .failure(error: wrapped)
            }
        }
    )
)

private let webSearchInputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

private let webSearchOutputJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "action": .object([
            "anyOf": .array([
                .object([
                    "type": .string("object"),
                    "required": .array([.string("type")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("search")])
                        ]),
                        "query": .object([
                            "type": .string("string")
                        ])
                    ])
                ]),
                .object([
                    "type": .string("object"),
                    "required": .array([.string("type")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("openPage")])
                        ]),
                        "url": .object([
                            "type": .array([.string("string"), .string("null")])
                        ])
                    ])
                ]),
                .object([
                    "type": .string("object"),
                    "required": .array([.string("type")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "type": .object([
                            "type": .string("string"),
                            "enum": .array([.string("findInPage")])
                        ]),
                        "url": .object([
                            "type": .array([.string("string"), .string("null")])
                        ]),
                        "pattern": .object([
                            "type": .array([.string("string"), .string("null")])
                        ])
                    ])
                ])
            ])
        ]),
        "sources": .object([
            "type": .string("array"),
            "items": .object([
                "anyOf": .array([
                    .object([
                        "type": .string("object"),
                        "required": .array([.string("type"), .string("url")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("url")])
                            ]),
                            "url": .object([
                                "type": .string("string")
                            ])
                        ])
                    ]),
                    .object([
                        "type": .string("object"),
                        "required": .array([.string("type"), .string("name")]),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "type": .object([
                                "type": .string("string"),
                                "enum": .array([.string("api")])
                            ]),
                            "name": .object([
                                "type": .string("string")
                            ])
                        ])
                    ])
                ])
            ])
        ])
    ])
])

public let openaiWebSearchToolFactory = createProviderToolFactoryWithOutputSchema(
    id: "openai.web_search",
    name: "web_search",
    inputSchema: FlexibleSchema(jsonSchema(webSearchInputJSONSchema)),
    outputSchema: FlexibleSchema(jsonSchema(webSearchOutputJSONSchema))
) { (args: OpenAIWebSearchArgs) in
    var options = ProviderToolFactoryWithOutputSchemaOptions()
    options.args = encodeOpenAIWebSearchArgs(args)
    return options
}

private func encodeOpenAIWebSearchArgs(_ args: OpenAIWebSearchArgs) -> [String: JSONValue] {
    var payload: [String: JSONValue] = [:]

    if let filters = args.filters {
        var filtersPayload: [String: JSONValue] = [:]
        if let allowed = filters.allowedDomains {
            filtersPayload["allowedDomains"] = .array(allowed.map(JSONValue.string))
        }
        if !filtersPayload.isEmpty {
            payload["filters"] = .object(filtersPayload)
        }
    }

    if let externalWebAccess = args.externalWebAccess {
        payload["externalWebAccess"] = .bool(externalWebAccess)
    }

    if let size = args.searchContextSize {
        payload["searchContextSize"] = .string(size)
    }

    if let location = args.userLocation {
        payload["userLocation"] = makeUserLocationJSON(location)
    }

    return payload
}

private func makeUserLocationJSON(_ location: OpenAIWebSearchArgs.UserLocation) -> JSONValue {
    var payload: [String: JSONValue] = [
        "type": .string(location.type.rawValue)
    ]
    if let country = location.country {
        payload["country"] = .string(country)
    }
    if let city = location.city {
        payload["city"] = .string(city)
    }
    if let region = location.region {
        payload["region"] = .string(region)
    }
    if let timezone = location.timezone {
        payload["timezone"] = .string(timezone)
    }
    return .object(payload)
}

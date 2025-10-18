import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIWebSearchArgs: Sendable, Equatable {
    public struct Filters: Sendable, Equatable {
        public let allowedDomains: [String]?
    }

    public struct UserLocation: Sendable, Equatable {
        public let country: String?
        public let city: String?
        public let region: String?
        public let timezone: String?
    }

    public let filters: Filters?
    public let searchContextSize: String?
    public let userLocation: UserLocation?
}

private let webSearchArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
        "filters": .object([
            "type": .array([.string("object"), .string("null")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "allowedDomains": .object([
                    "type": .array([.string("array"), .string("null")]),
                    "items": .object(["type": .string("string")])
                ])
            ])
        ]),
        "searchContextSize": .object([
            "type": .array([.string("string"), .string("null")]),
            "enum": .array([.string("low"), .string("medium"), .string("high")])
        ]),
        "userLocation": .object([
            "type": .array([.string("object"), .string("null")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "type": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "country": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "city": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "region": .object([
                    "type": .array([.string("string"), .string("null")])
                ]),
                "timezone": .object([
                    "type": .array([.string("string"), .string("null")])
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

                var filters: OpenAIWebSearchArgs.Filters?
                if let filtersValue = dict["filters"], filtersValue != .null {
                    guard case .object(let filtersObject) = filtersValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters must be an object")
                        return .failure(error: TypeValidationError.wrap(value: filtersValue, cause: error))
                    }
                    if let domainsValue = filtersObject["allowedDomains"], domainsValue != .null {
                        guard case .array(let array) = domainsValue else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "filters.allowedDomains must be an array")
                            return .failure(error: TypeValidationError.wrap(value: domainsValue, cause: error))
                        }
                        let allowedDomains = try array.map { element -> String in
                            guard case .string(let domain) = element else {
                                let error = SchemaValidationIssuesError(vendor: "openai", issues: "allowedDomains must contain strings")
                                throw TypeValidationError.wrap(value: element, cause: error)
                            }
                            return domain
                        }
                        filters = OpenAIWebSearchArgs.Filters(allowedDomains: allowedDomains)
                    } else {
                        filters = OpenAIWebSearchArgs.Filters(allowedDomains: nil)
                    }
                }

                var searchContextSize: String? = nil
                if let sizeValue = dict["searchContextSize"], sizeValue != .null {
                    guard case .string(let size) = sizeValue,
                          ["low", "medium", "high"].contains(size) else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "searchContextSize must be 'low', 'medium', or 'high'")
                        return .failure(error: TypeValidationError.wrap(value: sizeValue, cause: error))
                    }
                    searchContextSize = size
                }

                var userLocation: OpenAIWebSearchArgs.UserLocation? = nil
                if let locationValue = dict["userLocation"], locationValue != .null {
                    guard case .object(let locationObject) = locationValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation must be an object")
                        return .failure(error: TypeValidationError.wrap(value: locationValue, cause: error))
                    }
                    if let typeValue = locationObject["type"], typeValue != .null {
                        guard case .string(let typeString) = typeValue, typeString == "approximate" else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation.type must be 'approximate'")
                            return .failure(error: TypeValidationError.wrap(value: typeValue, cause: error))
                        }
                    }
                    func stringValue(_ key: String) throws -> String? {
                        guard let value = locationObject[key], value != .null else { return nil }
                        guard case .string(let string) = value else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "userLocation.\(key) must be a string")
                            throw TypeValidationError.wrap(value: value, cause: error)
                        }
                        return string
                    }
                    userLocation = OpenAIWebSearchArgs.UserLocation(
                        country: try stringValue("country"),
                        city: try stringValue("city"),
                        region: try stringValue("region"),
                        timezone: try stringValue("timezone")
                    )
                }

                let args = OpenAIWebSearchArgs(
                    filters: filters,
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

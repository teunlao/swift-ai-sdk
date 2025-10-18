import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAIWebSearchPreviewArgs: Sendable, Equatable {
    public let searchContextSize: String?
    public let userLocation: OpenAIWebSearchArgs.UserLocation?
}

private let webSearchPreviewArgsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(false),
    "properties": .object([
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

public let openaiWebSearchPreviewArgsSchema = FlexibleSchema<OpenAIWebSearchPreviewArgs>(
    Schema(
        jsonSchemaResolver: { webSearchPreviewArgsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
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

                let args = OpenAIWebSearchPreviewArgs(
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

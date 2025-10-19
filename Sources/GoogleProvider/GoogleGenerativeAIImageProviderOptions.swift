import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GoogleGenerativeAIPersonGeneration: String, Sendable, Equatable {
    case dontAllow = "dont_allow"
    case allowAdult = "allow_adult"
    case allowAll = "allow_all"
}

public enum GoogleGenerativeAIAspectRatio: String, Sendable, Equatable {
    case square = "1:1"
    case threeFour = "3:4"
    case fourThree = "4:3"
    case nineSixteen = "9:16"
    case sixteenNine = "16:9"
}

public struct GoogleGenerativeAIImageProviderOptions: Sendable, Equatable {
    public var personGeneration: GoogleGenerativeAIPersonGeneration?
    public var aspectRatio: GoogleGenerativeAIAspectRatio?

    public init(personGeneration: GoogleGenerativeAIPersonGeneration? = nil, aspectRatio: GoogleGenerativeAIAspectRatio? = nil) {
        self.personGeneration = personGeneration
        self.aspectRatio = aspectRatio
    }
}

private let imageOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let googleImageProviderOptionsSchema = FlexibleSchema(
    Schema<GoogleGenerativeAIImageProviderOptions>(
        jsonSchemaResolver: { imageOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "google",
                        issues: "image provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var personGeneration: GoogleGenerativeAIPersonGeneration? = nil
                if let personValue = dict["personGeneration"], personValue != .null {
                    guard case .string(let raw) = personValue,
                          let parsed = GoogleGenerativeAIPersonGeneration(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "personGeneration must be 'dont_allow', 'allow_adult', or 'allow_all'"
                        )
                        return .failure(error: TypeValidationError.wrap(value: personValue, cause: error))
                    }
                    personGeneration = parsed
                }

                var aspectRatio: GoogleGenerativeAIAspectRatio? = nil
                if let aspectValue = dict["aspectRatio"], aspectValue != .null {
                    guard case .string(let raw) = aspectValue,
                          let parsed = GoogleGenerativeAIAspectRatio(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "aspectRatio must be one of the supported ratios"
                        )
                        return .failure(error: TypeValidationError.wrap(value: aspectValue, cause: error))
                    }
                    aspectRatio = parsed
                }

                return .success(value: GoogleGenerativeAIImageProviderOptions(
                    personGeneration: personGeneration,
                    aspectRatio: aspectRatio
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

extension GoogleGenerativeAIImageProviderOptions {
    public func toDictionary() -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if let personGeneration {
            result["personGeneration"] = .string(personGeneration.rawValue)
        }
        if let aspectRatio {
            result["aspectRatio"] = .string(aspectRatio.rawValue)
        }
        return result
    }
}

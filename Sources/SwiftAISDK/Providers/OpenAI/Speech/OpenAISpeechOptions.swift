import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAISpeechProviderOptions: Sendable, Equatable {
    var instructions: String?
    var speed: Double?
}

private let openAISpeechProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

let openAISpeechProviderOptionsSchema = FlexibleSchema<OpenAISpeechProviderOptions>(
    Schema(
        jsonSchemaResolver: { openAISpeechProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAISpeechProviderOptions()

                if let instructionsValue = dict["instructions"], instructionsValue != .null {
                    guard case .string(let instructions) = instructionsValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "instructions must be a string")
                        return .failure(error: TypeValidationError.wrap(value: instructionsValue, cause: error))
                    }
                    options.instructions = instructions
                }

                if let speedValue = dict["speed"], speedValue != .null {
                    guard case .number(let number) = speedValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "speed must be a number")
                        return .failure(error: TypeValidationError.wrap(value: speedValue, cause: error))
                    }
                    if number < 0.25 || number > 4.0 {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "speed must be between 0.25 and 4.0")
                        return .failure(error: TypeValidationError.wrap(value: speedValue, cause: error))
                    }
                    options.speed = number
                }

                return .success(value: options)
            } catch let error as TypeValidationError {
                return .failure(error: error)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct OpenAISpeechModelOptions: Sendable, Equatable {
    public var instructions: String?
    public var speed: Double?

    public init(instructions: String? = nil, speed: Double? = nil) {
        self.instructions = instructions
        self.speed = speed
    }
}

private let openAISpeechModelOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "properties": .object([
        "instructions": .object(["type": .array([.string("string"), .string("null")])]),
        "speed": .object(["type": .array([.string("number"), .string("null")]),
            "minimum": .number(0.25), "maximum": .number(4.0)])
    ]),
    "additionalProperties": .bool(true)
])

public let openAISpeechModelOptionsSchema = FlexibleSchema<OpenAISpeechModelOptions>(
    Schema(
        jsonSchemaResolver: { openAISpeechModelOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAISpeechModelOptions()

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
                    if !number.isFinite || number < 0.25 || number > 4.0 {
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

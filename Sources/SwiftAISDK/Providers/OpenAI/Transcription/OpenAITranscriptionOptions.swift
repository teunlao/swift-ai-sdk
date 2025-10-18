import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAITranscriptionProviderOptions: Sendable, Equatable {
    var include: [String]?
    var language: String?
    var prompt: String?
    var temperature: Double?
    var timestampGranularities: [String]?
}

private let openAITranscriptionProviderOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

let openAITranscriptionProviderOptionsSchema = FlexibleSchema<OpenAITranscriptionProviderOptions>(
    Schema(
        jsonSchemaResolver: { openAITranscriptionProviderOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "openai", issues: "expected object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = OpenAITranscriptionProviderOptions(
                    include: nil,
                    language: nil,
                    prompt: nil,
                    temperature: 0,
                    timestampGranularities: ["segment"]
                )

                if let includeValue = dict["include"], includeValue != .null {
                    guard case .array(let array) = includeValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "include must be an array of strings")
                        return .failure(error: TypeValidationError.wrap(value: includeValue, cause: error))
                    }
                    var include: [String] = []
                    include.reserveCapacity(array.count)
                    for item in array {
                        guard case .string(let string) = item else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "include entries must be strings")
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        include.append(string)
                    }
                    options.include = include
                }

                if let languageValue = dict["language"], languageValue != .null {
                    guard case .string(let language) = languageValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "language must be a string")
                        return .failure(error: TypeValidationError.wrap(value: languageValue, cause: error))
                    }
                    options.language = language
                }

                if let promptValue = dict["prompt"], promptValue != .null {
                    guard case .string(let prompt) = promptValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "prompt must be a string")
                        return .failure(error: TypeValidationError.wrap(value: promptValue, cause: error))
                    }
                    options.prompt = prompt
                }

                if let temperatureValue = dict["temperature"], temperatureValue != .null {
                    guard case .number(let number) = temperatureValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "temperature must be a number")
                        return .failure(error: TypeValidationError.wrap(value: temperatureValue, cause: error))
                    }
                    if number < 0 || number > 1 {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "temperature must be between 0 and 1")
                        return .failure(error: TypeValidationError.wrap(value: temperatureValue, cause: error))
                    }
                    options.temperature = number
                }

                if let granularitiesValue = dict["timestampGranularities"], granularitiesValue != .null {
                    guard case .array(let array) = granularitiesValue else {
                        let error = SchemaValidationIssuesError(vendor: "openai", issues: "timestampGranularities must be an array")
                        return .failure(error: TypeValidationError.wrap(value: granularitiesValue, cause: error))
                    }
                    var granularities: [String] = []
                    granularities.reserveCapacity(array.count)
                    for item in array {
                        guard case .string(let granularity) = item else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "timestampGranularities entries must be strings")
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        guard granularity == "word" || granularity == "segment" else {
                            let error = SchemaValidationIssuesError(vendor: "openai", issues: "timestampGranularities must be 'word' or 'segment'")
                            return .failure(error: TypeValidationError.wrap(value: item, cause: error))
                        }
                        granularities.append(granularity)
                    }
                    options.timestampGranularities = granularities
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

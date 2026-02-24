import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GoogleGenerativeAIEmbeddingTaskType: String, Sendable, Equatable {
    case semanticSimilarity = "SEMANTIC_SIMILARITY"
    case classification = "CLASSIFICATION"
    case clustering = "CLUSTERING"
    case retrievalDocument = "RETRIEVAL_DOCUMENT"
    case retrievalQuery = "RETRIEVAL_QUERY"
    case questionAnswering = "QUESTION_ANSWERING"
    case factVerification = "FACT_VERIFICATION"
    case codeRetrievalQuery = "CODE_RETRIEVAL_QUERY"
}

public struct GoogleGenerativeAIEmbeddingProviderOptions: Sendable, Equatable {
    public var outputDimensionality: Double?
    public var taskType: GoogleGenerativeAIEmbeddingTaskType?

    public init(outputDimensionality: Double? = nil, taskType: GoogleGenerativeAIEmbeddingTaskType? = nil) {
        self.outputDimensionality = outputDimensionality
        self.taskType = taskType
    }
}

private let embeddingOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let googleGenerativeAIEmbeddingProviderOptionsSchema = FlexibleSchema(
    Schema<GoogleGenerativeAIEmbeddingProviderOptions>(
        jsonSchemaResolver: { embeddingOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "google",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var outputDimensionality: Double? = nil
                if let dimensionalityValue = dict["outputDimensionality"] {
                    if dimensionalityValue == .null {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "outputDimensionality must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: dimensionalityValue, cause: error))
                    }

                    guard case .number(let number) = dimensionalityValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "outputDimensionality must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: dimensionalityValue, cause: error))
                    }
                    outputDimensionality = number
                }

                var taskType: GoogleGenerativeAIEmbeddingTaskType? = nil
                if let taskTypeValue = dict["taskType"] {
                    if taskTypeValue == .null {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "taskType must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: taskTypeValue, cause: error))
                    }

                    guard case .string(let raw) = taskTypeValue,
                          let parsed = GoogleGenerativeAIEmbeddingTaskType(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "taskType must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: taskTypeValue, cause: error))
                    }
                    taskType = parsed
                }

                return .success(value: GoogleGenerativeAIEmbeddingProviderOptions(
                    outputDimensionality: outputDimensionality,
                    taskType: taskType
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

extension GoogleGenerativeAIEmbeddingProviderOptions {
    public func toDictionary() -> [String: Any] {
        var result: [String: Any] = [:]
        if let outputDimensionality {
            result["outputDimensionality"] = outputDimensionality
        }
        if let taskType {
            result["taskType"] = taskType.rawValue
        }
        return result
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

public enum GoogleEmbeddingTaskType: String, Sendable, Equatable {
    case semanticSimilarity = "SEMANTIC_SIMILARITY"
    case classification = "CLASSIFICATION"
    case clustering = "CLUSTERING"
    case retrievalDocument = "RETRIEVAL_DOCUMENT"
    case retrievalQuery = "RETRIEVAL_QUERY"
    case questionAnswering = "QUESTION_ANSWERING"
    case factVerification = "FACT_VERIFICATION"
    case codeRetrievalQuery = "CODE_RETRIEVAL_QUERY"
}

public struct GoogleEmbeddingModelOptions: Sendable, Equatable {
    public var outputDimensionality: Double?
    public var taskType: GoogleEmbeddingTaskType?
    public var content: [[JSONValue]?]?

    public init(outputDimensionality: Double? = nil, taskType: GoogleEmbeddingTaskType? = nil, content: [[JSONValue]?]? = nil) {
        self.outputDimensionality = outputDimensionality
        self.taskType = taskType
        self.content = content
    }
}

private let embeddingOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let googleGenerativeAIEmbeddingProviderOptionsSchema = FlexibleSchema(
    Schema<GoogleEmbeddingModelOptions>(
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

                var taskType: GoogleEmbeddingTaskType? = nil
                if let taskTypeValue = dict["taskType"] {
                    if taskTypeValue == .null {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "taskType must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: taskTypeValue, cause: error))
                    }

                    guard case .string(let raw) = taskTypeValue,
                          let parsed = GoogleEmbeddingTaskType(rawValue: raw) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "taskType must be a valid enum value"
                        )
                        return .failure(error: TypeValidationError.wrap(value: taskTypeValue, cause: error))
                    }
                    taskType = parsed
                }

                var content: [[JSONValue]?]?
                if let value = dict["content"] {
                    guard case .array(let entries) = value else {
                        throw SchemaValidationIssuesError(vendor: "google", issues: "content must be an array")
                    }
                    content = try entries.map { entry in
                        if entry == .null { return nil }
                        guard case .array(let parts) = entry, !parts.isEmpty else {
                            throw SchemaValidationIssuesError(vendor: "google", issues: "content entries must be nonempty arrays or null")
                        }
                        return try parts.map { part in
                            guard case .object(let object) = part else {
                                throw SchemaValidationIssuesError(vendor: "google", issues: "content parts must be objects")
                            }
                            if case .string = object["text"] { return .object(["text": object["text"]!]) }
                            for key in ["inlineData", "fileData"] {
                                let dataKey = key == "inlineData" ? "data" : "fileUri"
                                if case .object(let data) = object[key],
                                   case .string = data["mimeType"], case .string = data[dataKey] {
                                    return .object([key: .object(["mimeType": data["mimeType"]!, dataKey: data[dataKey]!])])
                                }
                            }
                            throw SchemaValidationIssuesError(vendor: "google", issues: "invalid embedding content part")
                        }
                    }
                }
                return .success(value: GoogleEmbeddingModelOptions(
                    outputDimensionality: outputDimensionality,
                    taskType: taskType,
                    content: content
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

extension GoogleEmbeddingModelOptions {
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

import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-embedding-options.ts
// Upstream commit: 8a5233b15b1e69573d63faee6cd0014559252ee4
//===----------------------------------------------------------------------===//

public struct GoogleVertexEmbeddingModelOptions: Sendable, Equatable {
    public var outputDimensionality: Double?
    public var taskType: GoogleEmbeddingTaskType?
    public var title: String?
    public var autoTruncate: Bool?

    public init(
        outputDimensionality: Double? = nil,
        taskType: GoogleEmbeddingTaskType? = nil,
        title: String? = nil,
        autoTruncate: Bool? = nil
    ) {
        self.outputDimensionality = outputDimensionality
        self.taskType = taskType
        self.title = title
        self.autoTruncate = autoTruncate
    }
}

private let googleVertexEmbeddingOptionsJsonSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

private func makeGoogleVertexEmbeddingModelOptionsSchema(
    vendor: String
) -> FlexibleSchema<GoogleVertexEmbeddingModelOptions> {
    FlexibleSchema(
        Schema<GoogleVertexEmbeddingModelOptions>(
            jsonSchemaResolver: { googleVertexEmbeddingOptionsJsonSchema },
            validator: { value in
                do {
                    let json = try jsonValue(from: value)
                    guard case .object(let dict) = json else {
                        let error = SchemaValidationIssuesError(
                            vendor: vendor,
                            issues: "provider options must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                    }

                    var outputDimensionality: Double? = nil
                    if let dimensionalityValue = dict["outputDimensionality"] {
                        if dimensionalityValue == .null {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
                                issues: "outputDimensionality must be a number"
                            )
                            return .failure(error: TypeValidationError.wrap(value: dimensionalityValue, cause: error))
                        }

                        guard case .number(let number) = dimensionalityValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
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
                                vendor: vendor,
                                issues: "taskType must be a valid enum value"
                            )
                            return .failure(error: TypeValidationError.wrap(value: taskTypeValue, cause: error))
                        }

                        guard case .string(let raw) = taskTypeValue,
                              let parsed = GoogleEmbeddingTaskType(rawValue: raw) else {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
                                issues: "taskType must be a valid enum value"
                            )
                            return .failure(error: TypeValidationError.wrap(value: taskTypeValue, cause: error))
                        }
                        taskType = parsed
                    }

                    var title: String? = nil
                    if let titleValue = dict["title"] {
                        if titleValue == .null {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
                                issues: "title must be a string"
                            )
                            return .failure(error: TypeValidationError.wrap(value: titleValue, cause: error))
                        }

                        guard case .string(let stringValue) = titleValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
                                issues: "title must be a string"
                            )
                            return .failure(error: TypeValidationError.wrap(value: titleValue, cause: error))
                        }
                        title = stringValue
                    }

                    var autoTruncate: Bool? = nil
                    if let autoTruncateValue = dict["autoTruncate"] {
                        if autoTruncateValue == .null {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
                                issues: "autoTruncate must be a boolean"
                            )
                            return .failure(error: TypeValidationError.wrap(value: autoTruncateValue, cause: error))
                        }

                        guard case .bool(let boolValue) = autoTruncateValue else {
                            let error = SchemaValidationIssuesError(
                                vendor: vendor,
                                issues: "autoTruncate must be a boolean"
                            )
                            return .failure(error: TypeValidationError.wrap(value: autoTruncateValue, cause: error))
                        }
                        autoTruncate = boolValue
                    }

                    return .success(
                        value: GoogleVertexEmbeddingModelOptions(
                            outputDimensionality: outputDimensionality,
                            taskType: taskType,
                            title: title,
                            autoTruncate: autoTruncate
                        )
                    )
                } catch {
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }
            }
        )
    )
}

public let googleVertexEmbeddingModelOptionsSchema = makeGoogleVertexEmbeddingModelOptionsSchema(vendor: "googleVertex")

extension GoogleVertexEmbeddingModelOptions {
    func toParametersDictionary() -> [String: JSONValue] {
        var parameters: [String: JSONValue] = [:]
        if let outputDimensionality {
            parameters["outputDimensionality"] = .number(outputDimensionality)
        }
        if let autoTruncate {
            parameters["autoTruncate"] = .bool(autoTruncate)
        }
        return parameters
    }
}

extension GoogleVertexEmbeddingModelOptions {
    func toInstanceOverrides() -> [String: JSONValue] {
        var result: [String: JSONValue] = [:]
        if let taskType {
            result["task_type"] = .string(taskType.rawValue)
        }
        if let title {
            result["title"] = .string(title)
        }
        return result
    }
}

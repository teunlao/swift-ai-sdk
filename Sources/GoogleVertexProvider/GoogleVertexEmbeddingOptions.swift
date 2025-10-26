import Foundation
import AISDKProvider
import AISDKProviderUtils
import GoogleProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/google-vertex/src/google-vertex-embedding-options.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct GoogleVertexEmbeddingProviderOptions: Sendable, Equatable {
    public var outputDimensionality: Int?
    public var taskType: GoogleGenerativeAIEmbeddingTaskType?
    public var title: String?
    public var autoTruncate: Bool?

    public init(
        outputDimensionality: Int? = nil,
        taskType: GoogleGenerativeAIEmbeddingTaskType? = nil,
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

public let googleVertexEmbeddingProviderOptionsSchema = FlexibleSchema(
    Schema<GoogleVertexEmbeddingProviderOptions>(
        jsonSchemaResolver: { googleVertexEmbeddingOptionsJsonSchema },
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

                var outputDimensionality: Int? = nil
                if let dimensionalityValue = dict["outputDimensionality"], dimensionalityValue != .null {
                    guard case .number(let number) = dimensionalityValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "outputDimensionality must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: dimensionalityValue, cause: error))
                    }

                    let intValue = Int(number)
                    if Double(intValue) != number {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "outputDimensionality must be an integer"
                        )
                        return .failure(error: TypeValidationError.wrap(value: dimensionalityValue, cause: error))
                    }

                    outputDimensionality = intValue
                }

                var taskType: GoogleGenerativeAIEmbeddingTaskType? = nil
                if let taskTypeValue = dict["taskType"], taskTypeValue != .null {
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

                var title: String? = nil
                if let titleValue = dict["title"], titleValue != .null {
                    guard case .string(let stringValue) = titleValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "title must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: titleValue, cause: error))
                    }
                    title = stringValue
                }

                var autoTruncate: Bool? = nil
                if let autoTruncateValue = dict["autoTruncate"], autoTruncateValue != .null {
                    guard case .bool(let boolValue) = autoTruncateValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "google",
                            issues: "autoTruncate must be a boolean"
                        )
                        return .failure(error: TypeValidationError.wrap(value: autoTruncateValue, cause: error))
                    }
                    autoTruncate = boolValue
                }

                return .success(
                    value: GoogleVertexEmbeddingProviderOptions(
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

extension GoogleVertexEmbeddingProviderOptions {
    func toParametersDictionary() -> [String: JSONValue] {
        var parameters: [String: JSONValue] = [:]
        if let outputDimensionality {
            parameters["outputDimensionality"] = .number(Double(outputDimensionality))
        }
        if let autoTruncate {
            parameters["autoTruncate"] = .bool(autoTruncate)
        }
        return parameters
    }
}

extension GoogleVertexEmbeddingProviderOptions {
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

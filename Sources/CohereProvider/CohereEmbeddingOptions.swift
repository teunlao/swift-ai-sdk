import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/cohere-embedding-options.ts (provider options)
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

public struct CohereEmbeddingOptions: Sendable, Equatable {
    public enum InputType: String, Sendable, Equatable {
        case searchDocument = "search_document"
        case searchQuery = "search_query"
        case classification
        case clustering
    }

    public enum Truncate: String, Sendable, Equatable {
        case none = "NONE"
        case start = "START"
        case end = "END"
    }

    public var inputType: InputType?
    public var truncate: Truncate?

    public init(inputType: InputType? = nil, truncate: Truncate? = nil) {
        self.inputType = inputType
        self.truncate = truncate
    }
}

private let cohereEmbeddingOptionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true)
])

public let cohereEmbeddingOptionsSchema = FlexibleSchema(
    Schema<CohereEmbeddingOptions>(
        jsonSchemaResolver: { cohereEmbeddingOptionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "cohere",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = CohereEmbeddingOptions()

                if let inputTypeValue = dict["inputType"], inputTypeValue != .null {
                    guard case .string(let inputTypeString) = inputTypeValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "inputType must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: inputTypeValue, cause: error))
                    }

                    guard let resolved = CohereEmbeddingOptions.InputType(rawValue: inputTypeString) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "inputType must be one of search_document, search_query, classification, clustering"
                        )
                        return .failure(error: TypeValidationError.wrap(value: inputTypeValue, cause: error))
                    }

                    options.inputType = resolved
                }

                if let truncateValue = dict["truncate"], truncateValue != .null {
                    guard case .string(let truncateString) = truncateValue else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "truncate must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: truncateValue, cause: error))
                    }

                    guard let resolved = CohereEmbeddingOptions.Truncate(rawValue: truncateString) else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "truncate must be one of NONE, START, END"
                        )
                        return .failure(error: TypeValidationError.wrap(value: truncateValue, cause: error))
                    }

                    options.truncate = resolved
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

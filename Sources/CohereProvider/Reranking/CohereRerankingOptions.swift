import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/cohere/src/reranking/cohere-reranking-options.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct CohereRerankingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension CohereRerankingModelId {
    static let rerankV35: Self = "rerank-v3.5"
    static let rerankEnglishV30: Self = "rerank-english-v3.0"
    static let rerankMultilingualV30: Self = "rerank-multilingual-v3.0"
}

public struct CohereRerankingOptions: Sendable, Equatable {
    /// Long documents will be automatically truncated to the specified number of tokens. Default: 4096.
    public var maxTokensPerDoc: Int?

    /// Priority of the request. Default: 0.
    public var priority: Int?

    public init(maxTokensPerDoc: Int? = nil, priority: Int? = nil) {
        self.maxTokensPerDoc = maxTokensPerDoc
        self.priority = priority
    }
}

private let optionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
])

public let cohereRerankingOptionsSchema = FlexibleSchema(
    Schema<CohereRerankingOptions>(
        jsonSchemaResolver: { optionsJSONSchema },
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

                var options = CohereRerankingOptions()

                if let rawMaxTokensPerDoc = dict["maxTokensPerDoc"], rawMaxTokensPerDoc != .null {
                    guard case .number(let number) = rawMaxTokensPerDoc else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "maxTokensPerDoc must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawMaxTokensPerDoc, cause: error))
                    }

                    let intValue = Int(number)
                    if Double(intValue) != number {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "maxTokensPerDoc must be an integer"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawMaxTokensPerDoc, cause: error))
                    }
                    options.maxTokensPerDoc = intValue
                }

                if let rawPriority = dict["priority"], rawPriority != .null {
                    guard case .number(let number) = rawPriority else {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "priority must be a number"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawPriority, cause: error))
                    }

                    let intValue = Int(number)
                    if Double(intValue) != number {
                        let error = SchemaValidationIssuesError(
                            vendor: "cohere",
                            issues: "priority must be an integer"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawPriority, cause: error))
                    }
                    options.priority = intValue
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)


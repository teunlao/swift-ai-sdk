import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/togetherai/src/reranking/togetherai-reranking-model-options.ts
// Upstream commit: 8a5233b
//===----------------------------------------------------------------------===//

public struct TogetherAIRerankingModelOptions: Codable, Sendable, Equatable {
    /// List of keys in the JSON object document to rank by.
    /// Defaults to use all supplied keys for ranking.
    public var rankFields: [String]?

    public init(rankFields: [String]? = nil) {
        self.rankFields = rankFields
    }
}

private let optionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
])

public let togetheraiRerankingModelOptionsSchema = FlexibleSchema(
    Schema<TogetherAIRerankingModelOptions>(
        jsonSchemaResolver: { optionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "togetherai",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = TogetherAIRerankingModelOptions()

                if let rawRankFields = dict["rankFields"] {
                    guard case .array(let values) = rawRankFields else {
                        let error = SchemaValidationIssuesError(
                            vendor: "togetherai",
                            issues: "rankFields must be an array of strings"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawRankFields, cause: error))
                    }

                    var fields: [String] = []
                    fields.reserveCapacity(values.count)
                    for entry in values {
                        guard case .string(let str) = entry else {
                            let error = SchemaValidationIssuesError(
                                vendor: "togetherai",
                                issues: "rankFields must be an array of strings"
                            )
                            return .failure(error: TypeValidationError.wrap(value: rawRankFields, cause: error))
                        }
                        fields.append(str)
                    }
                    options.rankFields = fields
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)


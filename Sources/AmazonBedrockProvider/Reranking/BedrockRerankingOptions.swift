import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/amazon-bedrock/src/reranking/bedrock-reranking-options.ts
// Upstream commit: f3a72bc2a
//===----------------------------------------------------------------------===//

public struct BedrockRerankingModelId: RawRepresentable, Hashable, Sendable, ExpressibleByStringLiteral {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(stringLiteral value: StringLiteralType) {
        self.init(rawValue: value)
    }
}

public extension BedrockRerankingModelId {
    static let amazonRerankV1_0: Self = "amazon.rerank-v1:0"
    static let cohereRerankV3_5_0: Self = "cohere.rerank-v3-5:0"
}

public struct BedrockRerankingOptions: Sendable, Equatable {
    /// Pagination token for returning the next batch of results.
    public var nextToken: String?

    /// Additional model request fields to pass to the model.
    public var additionalModelRequestFields: [String: JSONValue]?

    public init(
        nextToken: String? = nil,
        additionalModelRequestFields: [String: JSONValue]? = nil
    ) {
        self.nextToken = nextToken
        self.additionalModelRequestFields = additionalModelRequestFields
    }
}

private let optionsJSONSchema: JSONValue = .object([
    "type": .string("object"),
    "additionalProperties": .bool(true),
])

public let bedrockRerankingOptionsSchema = FlexibleSchema(
    Schema<BedrockRerankingOptions>(
        jsonSchemaResolver: { optionsJSONSchema },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(
                        vendor: "bedrock",
                        issues: "provider options must be an object"
                    )
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                var options = BedrockRerankingOptions()

                if let rawNextToken = dict["nextToken"], rawNextToken != .null {
                    guard case .string(let token) = rawNextToken else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "nextToken must be a string"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawNextToken, cause: error))
                    }
                    options.nextToken = token
                }

                if let rawAdditionalFields = dict["additionalModelRequestFields"], rawAdditionalFields != .null {
                    guard case .object(let fields) = rawAdditionalFields else {
                        let error = SchemaValidationIssuesError(
                            vendor: "bedrock",
                            issues: "additionalModelRequestFields must be an object"
                        )
                        return .failure(error: TypeValidationError.wrap(value: rawAdditionalFields, cause: error))
                    }
                    options.additionalModelRequestFields = fields
                }

                return .success(value: options)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)


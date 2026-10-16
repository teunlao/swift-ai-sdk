import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAICompatibleProvider

public struct CerebrasErrorData: Codable, Sendable, Equatable {
    public let message: String
    public let type: String
    public let param: String
    public let code: String
}
private let cerebrasErrorSchema = FlexibleSchema(Schema<CerebrasErrorData>.codable(CerebrasErrorData.self, jsonSchema: ["type": "object"]))
private struct CerebrasErrorExtraction: Error {}
public let cerebrasErrorConfiguration = OpenAICompatibleErrorConfiguration(
    errorSchema: cerebrasErrorSchema,
    errorToMessage: { $0.message },
    extractMessage: { value in
        guard case .object(let object) = value, case .string(let message) = object["message"] else { throw CerebrasErrorExtraction() }
        return message
    }
)

import Foundation
import AISDKProvider
import AISDKProviderUtils

extension GenerateObjectResult: Encodable where ResultValue: Encodable {
    public func encode(to encoder: Encoder) throws {
        try jsonValue().encode(to: encoder)
    }
}

public extension GenerateObjectResult where ResultValue: Encodable {
    func jsonValue() -> JSONValue {
        GenerateObjectResultJSONEncoder.serialize(result: self)
    }

    func jsonString(prettyPrinted: Bool = true, sortedKeys: Bool = true) throws -> String {
        try jsonValue().toJSONString(prettyPrinted: prettyPrinted, sortedKeys: sortedKeys)
    }
}

private enum GenerateObjectResultJSONEncoder {
    static func serialize<ResultValue: Encodable>(result: GenerateObjectResult<ResultValue>) -> JSONValue {
        var object: [String: JSONValue] = [:]
        object["object"] = encodeObject(result.object)
        object["reasoning"] = result.reasoning.map(JSONValue.string) ?? .null
        object["finishReason"] = .string(result.finishReason.rawValue)
        object["usage"] = usage(result.usage)
        object["warnings"] = warnings(result.warnings)
        object["request"] = request(result.request)
        object["response"] = response(result.response)
        object["providerMetadata"] = providerMetadata(result.providerMetadata) ?? .null
        return .object(object)
    }

    private static func encodeObject<ResultValue: Encodable>(_ object: ResultValue) -> JSONValue {
        if let json = object as? JSONValue {
            return json
        }
        if let dictionary = object as? [String: JSONValue] {
            return .object(dictionary)
        }
        if let array = object as? [JSONValue] {
            return .array(array)
        }
        if let jsonValue = JSONValueEncoding.jsonValue(from: object) {
            return jsonValue
        }
        return .string(String(describing: object))
    }

    private static func usage(_ usage: LanguageModelUsage) -> JSONValue {
        .object([
            "inputTokens": usage.inputTokens.map { .number(Double($0)) } ?? .null,
            "outputTokens": usage.outputTokens.map { .number(Double($0)) } ?? .null,
            "totalTokens": usage.totalTokens.map { .number(Double($0)) } ?? .null,
            "reasoningTokens": usage.reasoningTokens.map { .number(Double($0)) } ?? .null,
            "cachedInputTokens": usage.cachedInputTokens.map { .number(Double($0)) } ?? .null
        ])
    }

    private static func warnings(_ warnings: [CallWarning]?) -> JSONValue {
        guard let warnings else { return .null }
        return .array(warnings.map(warning))
    }

    private static func warning(_ warning: CallWarning) -> JSONValue {
        switch warning {
        case .unsupported(let feature, let details):
            return .object([
                "type": .string("unsupported"),
                "feature": .string(feature),
                "details": details.map(JSONValue.string) ?? .null
            ])
        case .compatibility(let feature, let details):
            return .object([
                "type": .string("compatibility"),
                "feature": .string(feature),
                "details": details.map(JSONValue.string) ?? .null
            ])
        case .other(let message):
            return .object([
                "type": .string("other"),
                "message": .string(message)
            ])
        }
    }

    private static func request(_ metadata: LanguageModelRequestMetadata) -> JSONValue {
        .object([
            "body": metadata.body ?? .null
        ])
    }

    private static func response(_ response: LanguageModelResponseMetadataWithBody) -> JSONValue {
        var map: [String: JSONValue] = [
            "id": .string(response.id),
            "timestamp": .string(JSONValueEncoding.isoString(from: response.timestamp)),
            "modelId": .string(response.modelId)
        ]
        if let headers = response.headers {
            map["headers"] = .object(headers.mapValues(JSONValue.string))
        }
        if let body = response.body {
            map["body"] = body
        }
        return .object(map)
    }

    private static func providerMetadata(_ metadata: ProviderMetadata?) -> JSONValue? {
        guard let metadata else { return nil }
        return .object(metadata.mapValues { .object($0) })
    }
}

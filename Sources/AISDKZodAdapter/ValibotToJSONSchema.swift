/**
 Valibot schema to JSON Schema converter.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/valibot-to-json-schema.ts`.
 */
import Foundation
import AISDKProvider

public protocol ValibotJSONSchemaConvertible: Sendable {
    func toJsonSchema() -> JSONValue
}

public func valibotToJSONSchema(_ schema: Any) -> @Sendable () async throws -> JSONValue {
    if let convertible = schema as? ValibotJSONSchemaConvertible {
        return {
            convertible.toJsonSchema()
        }
    }

    return {
        throw ToJSONSchemaConversionError.moduleUnavailable("@valibot/to-json-schema")
    }
}

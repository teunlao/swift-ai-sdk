/**
 ArkType schema to JSON Schema converter.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/arktype-to-json-schema.ts`.
 */
import Foundation
import AISDKProvider

public protocol ArkTypeJSONSchemaConvertible: Sendable {
    func toJsonSchema() -> JSONValue
}

public func arktypeToJSONSchema(_ schema: ArkTypeJSONSchemaConvertible) -> () -> JSONValue {
    let convertible = schema
    return {
        convertible.toJsonSchema()
    }
}

/**
 Effect schema to JSON Schema converter.

 Port of `@ai-sdk/provider-utils/src/to-json-schema/effect-to-json-schema.ts`.
 */
import Foundation
import AISDKProvider

public enum ToJSONSchemaConversionError: Error, CustomStringConvertible, Sendable {
    case moduleUnavailable(String)

    public var description: String {
        switch self {
        case .moduleUnavailable(let module):
            return "Failed to import module '\(module)'"
        }
    }
}

public protocol EffectJSONSchemaConvertible: Sendable {
    func makeJSONSchema() -> JSONValue
}

public func effectToJSONSchema(_ schema: Any) -> @Sendable () async throws -> JSONValue {
    if let convertible = schema as? EffectJSONSchemaConvertible {
        return {
            convertible.makeJSONSchema()
        }
    }

    return {
        throw ToJSONSchemaConversionError.moduleUnavailable("effect")
    }
}

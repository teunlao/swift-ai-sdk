import Foundation
import AISDKProvider
import AISDKProviderUtils
import OpenAPIReflection

public enum JSONSchemaGenerator {
    private static let cacheBox = SchemaCache()

    public static func generate<T: Decodable & Sendable>(for type: T.Type) -> JSONValue {
        let key = ObjectIdentifier(type)

        cacheBox.lock.lock()
        if let cached = cacheBox.storage[key] {
            cacheBox.lock.unlock()
            return cached
        }
        cacheBox.lock.unlock()

        let schema = resolveSchema(for: type) ?? JSONValue.object([
            "type": .string("object"),
            "additionalProperties": .bool(true)
        ])

        cacheBox.lock.lock()
        cacheBox.storage[key] = schema
        cacheBox.lock.unlock()

        return schema
    }
}

private extension JSONSchemaGenerator {
    static func resolveSchema<T: Decodable & Sendable>(for type: T.Type) -> JSONValue? {
        do {
            let sample = try DefaultValueFactory.make(type)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]

            let jsonSchema = try genericOpenAPISchemaGuess(for: sample, using: encoder)
            let data = try JSONEncoder().encode(jsonSchema)
            let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
            return try jsonValue(from: object)
        } catch {
            return nil
        }
    }
}

private final class SchemaCache: @unchecked Sendable {
    let lock = NSLock()
    var storage: [ObjectIdentifier: JSONValue] = [:]
}

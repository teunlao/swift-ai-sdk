import Foundation
import AISDKProvider
import AISDKProviderUtils
import AISDKZodAdapter

public extension FlexibleSchema where Output: Decodable & Sendable {
    static func auto(_ type: Output.Type) -> FlexibleSchema<Output> {
        let jsonSchema = JSONSchemaGenerator.generate(for: type)
        return FlexibleSchema(Schema.codable(type, jsonSchema: jsonSchema))
    }
}

public extension FlexibleSchema {
    static func fromZod<Value: Decodable & Sendable>(
        _ type: Value.Type,
        zod: ZodSchema
    ) -> FlexibleSchema<Value> {
        let schema: Schema<Value> = schemaFromZod3(type, zod: zod)
        return FlexibleSchema<Value>(schema)
    }
}

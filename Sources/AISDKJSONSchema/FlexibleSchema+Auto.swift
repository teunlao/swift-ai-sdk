import Foundation
import AISDKProvider
import AISDKProviderUtils
import AISDKZodAdapter


public extension FlexibleSchema where Output: Codable & Sendable {
    static func jsonSchema(_ jsonSchema: JSONValue, as type: Output.Type = Output.self) -> FlexibleSchema<Output> {
        FlexibleSchema(Schema.codable(type, jsonSchema: jsonSchema))
    }

    static func jsonSchema(_ schemaResolver: @escaping @Sendable () -> JSONValue, as type: Output.Type = Output.self) -> FlexibleSchema<Output> {
        FlexibleSchema(Schema.codable(type, jsonSchema: schemaResolver()))
    }
}

public extension FlexibleSchema where Output: Codable & Sendable {
    static func auto(_ type: Output.Type) -> FlexibleSchema<Output> {
        let jsonSchema = JSONSchemaGenerator.generate(for: type)
        return FlexibleSchema(Schema.codable(type, jsonSchema: jsonSchema, configureDecoder: { decoder in
            // Use custom ISO8601 decoder that supports fractional seconds (.000)
            // This matches Zod's z.string().datetime() validation behavior
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateString = try container.decode(String.self)

                // Create formatter inside closure to avoid Sendable capture issues
                let formatter = ISO8601DateFormatter()

                // Try with fractional seconds first (e.g., "2025-10-24T00:00:00.000Z")
                formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                // Fallback to standard ISO8601 without fractional seconds (e.g., "2025-10-24T00:00:00Z")
                formatter.formatOptions = [.withInternetDateTime]
                if let date = formatter.date(from: dateString) {
                    return date
                }

                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Expected date string to be ISO8601-formatted."
                )
            }
            return decoder
        }))
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

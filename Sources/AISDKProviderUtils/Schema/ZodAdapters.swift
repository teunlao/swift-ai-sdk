import Foundation
import AISDKProvider
import AISDKZodAdapter

// Public adapters to build Schema/FlexibleSchema from the internal Swift Zod v3 DSL.
// This does NOT introduce a dependency on JS Zod; it converts our ZodSchema to JSON Schema
// and then uses existing jsonSchema helpers. Intended for developer ergonomics when JSON Schema
// is cumbersome to write by hand.

public func schemaFromZod3(
    _ zod: ZodSchema,
    options: Zod3Options? = nil
) -> Schema<JSONValue> {
    let effective: Zod3Options = options ?? .partial(PartialOptions(name: nil, refStrategy: RefStrategy.none, nameStrategy: NameStrategy.ref))
    let js = zod3ToJSONSchema(zod, options: effective)
    return jsonSchema(js)
}

public func schemaFromZod3<Output: Decodable & Sendable>(
    _ type: Output.Type,
    zod: ZodSchema,
    options: Zod3Options? = nil,
    configureDecoder: (@Sendable (JSONDecoder) -> JSONDecoder)? = nil
) -> Schema<Output> {
    let effective: Zod3Options = options ?? .partial(PartialOptions(name: nil, refStrategy: RefStrategy.none, nameStrategy: NameStrategy.ref))
    let js = zod3ToJSONSchema(zod, options: effective)
    return Schema.codable(Output.self, jsonSchema: js, configureDecoder: configureDecoder)
}

public func flexibleSchemaFromZod3<Output>(
    _ zod: ZodSchema,
    options: Zod3Options? = nil
) -> FlexibleSchema<Output> {
    if Output.self == JSONValue.self {
        let s: Schema<JSONValue> = schemaFromZod3(zod, options: options)
        // swiftlint:disable force_cast
        return FlexibleSchema(s as! Schema<Output>)
        // swiftlint:enable force_cast
    }
    // For non-JSONValue outputs, provide JSON Schema without typed decoding.
    let effective: Zod3Options = options ?? .partial(PartialOptions(name: nil, refStrategy: RefStrategy.none, nameStrategy: NameStrategy.title))
    let js = zod3ToJSONSchema(zod, options: effective)
    let s: Schema<Output> = jsonSchema(js, validate: nil)
    return FlexibleSchema(s)
}

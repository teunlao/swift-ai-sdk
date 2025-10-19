import Foundation

// Lightweight Zod-like facade: z.string / z.number / z.object / z.array / z.optional / z.nullable
// Mirrors popular ergonomics; under the hood uses existing builders that return ZodSchema.

public enum z {
    public static func string(
        minLength: Int? = nil,
        maxLength: Int? = nil,
        email: Bool = false,
        url: Bool = false,
        regex: (pattern: String, flags: String)? = nil
    ) -> ZodSchema {
        zodString(minLength: minLength, maxLength: maxLength, email: email, url: url, regex: regex)
    }

    public static func number(
        min: Double? = nil,
        max: Double? = nil,
        integer: Bool = false
    ) -> ZodSchema {
        zodNumber(min: min, max: max, integer: integer)
    }

    public static func boolean() -> ZodSchema { zodBoolean() }

    public static func array(
        of element: ZodSchema,
        minItems: Int? = nil,
        maxItems: Int? = nil
    ) -> ZodSchema {
        zodArray(of: element, minItems: minItems, maxItems: maxItems)
    }

    public static func object(_ properties: [String: ZodSchema], unknownKeysStrip: Bool = true)
        -> ZodSchema
    {
        zodObject(properties, unknownKeysStrip: unknownKeysStrip)
    }

    public static func optional(_ schema: ZodSchema) -> ZodSchema { zodOptional(schema) }
    public static func nullable(_ schema: ZodSchema) -> ZodSchema { zodNullable(schema) }
    public static func union(_ schemas: [ZodSchema]) -> ZodSchema { ZodSchema(ZodUnionDef(options: schemas)) }
}

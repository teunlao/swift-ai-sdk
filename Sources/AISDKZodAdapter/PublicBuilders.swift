import Foundation

// Public convenience builders for constructing ZodSchema without exposing
// low-level Zod*Def types. These functions live inside AISDKZodAdapter so
// they can use internal definitions and return public ZodSchema.

public func zodString(minLength: Int? = nil, maxLength: Int? = nil, email: Bool = false, url: Bool = false, regex: (pattern: String, flags: String)? = nil) -> ZodSchema {
    var checks: [ZodStringCheck] = []
    if let minLength { checks.append(.min(value: minLength, message: nil)) }
    if let maxLength { checks.append(.max(value: maxLength, message: nil)) }
    if email { checks.append(.email(message: nil)) }
    if url { checks.append(.url(message: nil)) }
    if let regex { checks.append(.regex(pattern: ZodRegexPattern(pattern: regex.pattern, flags: regex.flags), message: nil)) }
    return ZodSchema(ZodStringDef(checks: checks))
}

public func zodNumber(min: Double? = nil, max: Double? = nil, integer: Bool = false) -> ZodSchema {
    var checks: [ZodNumberCheck] = []
    if let min { checks.append(.min(ZodNumericBound<Double>(value: min, inclusive: true))) }
    if let max { checks.append(.max(ZodNumericBound<Double>(value: max, inclusive: true))) }
    if integer { checks.append(.int) }
    return ZodSchema(ZodNumberDef(checks: checks))
}

public func zodBoolean() -> ZodSchema { ZodSchema(ZodBooleanDef()) }

public func zodArray(of element: ZodSchema, minItems: Int? = nil, maxItems: Int? = nil) -> ZodSchema {
    let min = minItems.map { ZodArraySizeCheck(value: $0) }
    let max = maxItems.map { ZodArraySizeCheck(value: $0) }
    return ZodSchema(ZodArrayDef(type: element, minLength: min, maxLength: max, exactLength: nil))
}

public func zodObject(_ properties: [String: ZodSchema], unknownKeysStrip: Bool = true) -> ZodSchema {
    let unknown: ZodObjectUnknownKeys = unknownKeysStrip ? .strip : .passthrough
    return ZodSchema(ZodObjectDef(shape: { properties }, unknownKeys: unknown, catchall: ZodSchema.any()))
}

public func zodOptional(_ schema: ZodSchema) -> ZodSchema { ZodSchema(ZodOptionalDef(innerType: schema)) }
public func zodNullable(_ schema: ZodSchema) -> ZodSchema { ZodSchema(ZodNullableDef(innerType: schema)) }


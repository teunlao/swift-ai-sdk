@testable import AISDKProviderUtils

enum TestZod {
    static func string(_ checks: [ZodStringCheck] = []) -> ZodSchema {
        ZodSchema(ZodStringDef(checks: checks))
    }

    static func number(_ checks: [ZodNumberCheck] = []) -> ZodSchema {
        ZodSchema(ZodNumberDef(checks: checks))
    }

    static func bigint(_ checks: [ZodBigIntCheck] = []) -> ZodSchema {
        ZodSchema(ZodBigIntDef(checks: checks))
    }

    static func boolean() -> ZodSchema {
        ZodSchema(ZodBooleanDef())
    }

    static func date(_ checks: [ZodDateCheck] = []) -> ZodSchema {
        ZodSchema(ZodDateDef(checks: checks))
    }

    static func literal(_ value: Any) -> ZodSchema {
        ZodSchema(ZodLiteralDef(value: value))
    }

    static func enumeration(_ values: [String]) -> ZodSchema {
        ZodSchema(ZodEnumDef(values: values))
    }

    static func nativeEnum(_ values: [String: ZodNativeEnumValue]) -> ZodSchema {
        ZodSchema(ZodNativeEnumDef(values: values))
    }

    static func any() -> ZodSchema {
        ZodSchema(ZodAnyDef())
    }

    static func unknown() -> ZodSchema {
        ZodSchema(ZodUnknownDef())
    }

    static func never() -> ZodSchema {
        ZodSchema(ZodNeverDef())
    }

    static func array(
        of element: ZodSchema,
        min: Int? = nil,
        max: Int? = nil,
        exact: Int? = nil
    ) -> ZodSchema {
        let minLength = min.map { ZodArraySizeCheck(value: $0) }
        let maxLength = max.map { ZodArraySizeCheck(value: $0) }
        let exactLength = exact.map { ZodArraySizeCheck(value: $0) }
        return ZodSchema(
            ZodArrayDef(
                type: element,
                minLength: minLength,
                maxLength: maxLength,
                exactLength: exactLength
            )
        )
    }

    static func tuple(_ items: [ZodSchema], rest: ZodSchema? = nil) -> ZodSchema {
        ZodSchema(ZodTupleDef(items: items, rest: rest))
    }

    static func union(_ options: [ZodSchema]) -> ZodSchema {
        ZodSchema(ZodUnionDef(options: options))
    }

    static func discriminatedUnion(
        discriminator: String,
        cases: [(String, ZodSchema)]
    ) -> ZodSchema {
        ZodSchema(ZodDiscriminatedUnionDef(discriminator: discriminator, options: cases))
    }

    static func intersection(_ left: ZodSchema, _ right: ZodSchema) -> ZodSchema {
        ZodSchema(ZodIntersectionDef(left: left, right: right))
    }

    static func record(key: ZodSchema, value: ZodSchema) -> ZodSchema {
        ZodSchema(ZodRecordDef(keyType: key, valueType: value))
    }

    static func map(key: ZodSchema, value: ZodSchema) -> ZodSchema {
        ZodSchema(ZodMapDef(keyType: key, valueType: value))
    }

    static func set(of value: ZodSchema, min: Int? = nil, max: Int? = nil) -> ZodSchema {
        ZodSchema(
            ZodSetDef(
                valueType: value,
                minSize: min.map { ZodSetSizeCheck(value: $0) },
                maxSize: max.map { ZodSetSizeCheck(value: $0) }
            )
        )
    }

    static func optional(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodOptionalDef(innerType: schema))
    }

    static func nullable(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodNullableDef(innerType: schema))
    }

    static func `default`(_ schema: ZodSchema, value: @escaping @Sendable () -> Any) -> ZodSchema {
        ZodSchema(ZodDefaultDef(innerType: schema, defaultValue: value))
    }

    static func branded(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodBrandedDef(type: schema))
    }

    static func readonly(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodReadonlyDef(innerType: schema))
    }

    static func catching(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodCatchDef(innerType: schema))
    }

    static func promise(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodPromiseDef(type: schema))
    }

    static func effects(_ schema: ZodSchema) -> ZodSchema {
        ZodSchema(ZodEffectsDef(schema: schema))
    }

    static func pipeline(input: ZodSchema, output: ZodSchema) -> ZodSchema {
        ZodSchema(ZodPipelineDef(input: input, output: output))
    }

    static func lazy(_ builder: @escaping @Sendable () -> ZodSchema) -> ZodSchema {
        ZodSchema(ZodLazyDef(getter: builder))
    }

    static func object(
        _ properties: [String: ZodSchema],
        unknownKeys: ZodObjectUnknownKeys = .strip,
        catchall: ZodSchema = TestZod.never()
    ) -> ZodSchema {
        ZodSchema(
            ZodObjectDef(
                shape: { properties },
                unknownKeys: unknownKeys,
                catchall: catchall
            )
        )
    }
}

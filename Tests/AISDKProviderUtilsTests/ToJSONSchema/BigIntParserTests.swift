import Testing
@testable import AISDKProviderUtils

@Suite("BigInt Parser")
struct BigIntParserTests {
    @Test("basic bigint")
    func basicBigInt() {
        let schema = parseBigintDef(TestZod.bigint()._def as! ZodBigIntDef)
        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("integer"),
            "format": .string("int64")
        ])
    }

    @Test("gte and lte")
    func gteLte() {
        let schema = parseBigintDef(
            TestZod.bigint([
                .min(ZodNumericBound(value: 10, inclusive: true)),
                .max(ZodNumericBound(value: 20, inclusive: true))
            ])._def as! ZodBigIntDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("integer"),
            "format": .string("int64"),
            "minimum": .number(10),
            "maximum": .number(20)
        ])
    }

    @Test("gt and lt")
    func gtLt() {
        let schema = parseBigintDef(
            TestZod.bigint([
                .min(ZodNumericBound(value: 10, inclusive: false)),
                .max(ZodNumericBound(value: 20, inclusive: false))
            ])._def as! ZodBigIntDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("integer"),
            "format": .string("int64"),
            "exclusiveMinimum": .number(10),
            "exclusiveMaximum": .number(20)
        ])
    }

    @Test("multipleOf")
    func multipleOf() {
        let schema = parseBigintDef(
            TestZod.bigint([
                .multipleOf(5)
            ])._def as! ZodBigIntDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("integer"),
            "format": .string("int64"),
            "multipleOf": .number(5)
        ])
    }
}

import Testing
@testable import AISDKZodAdapter

@Suite("Number Parser")
struct NumberParserTests {
    @Test("minimum number")
    func minimumNumber() {
        let schema = parseNumberDef(
            TestZod.number([
                .min(ZodNumericBound(value: 5, inclusive: true))
            ])._def as! ZodNumberDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("number"),
            "minimum": .number(5)
        ])
    }

    @Test("maximum number")
    func maximumNumber() {
        let schema = parseNumberDef(
            TestZod.number([
                .max(ZodNumericBound(value: 5, inclusive: true))
            ])._def as! ZodNumberDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("number"),
            "maximum": .number(5)
        ])
    }

    @Test("min and max")
    func minAndMax() {
        let schema = parseNumberDef(
            TestZod.number([
                .min(ZodNumericBound(value: 5, inclusive: true)),
                .max(ZodNumericBound(value: 5, inclusive: true))
            ])._def as! ZodNumberDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("number"),
            "minimum": .number(5),
            "maximum": .number(5)
        ])
    }

    @Test("integer")
    func integer() {
        let schema = parseNumberDef(
            TestZod.number([.int])._def as! ZodNumberDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("integer")
        ])
    }

    @Test("multipleOf")
    func multipleOf() {
        let schema = parseNumberDef(
            TestZod.number([
                .multipleOf(2)
            ])._def as! ZodNumberDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("number"),
            "multipleOf": .number(2)
        ])
    }

    @Test("positive negative nonpositive nonnegative")
    func signChecks() {
        let schema = parseNumberDef(
            TestZod.number([
                .min(ZodNumericBound(value: 0, inclusive: false)),
                .max(ZodNumericBound(value: 0, inclusive: false)),
                .max(ZodNumericBound(value: 0, inclusive: true)),
                .min(ZodNumericBound(value: 0, inclusive: true))
            ])._def as! ZodNumberDef
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("number"),
            "minimum": .number(0),
            "maximum": .number(0),
            "exclusiveMaximum": .number(0),
            "exclusiveMinimum": .number(0)
        ])
    }
}

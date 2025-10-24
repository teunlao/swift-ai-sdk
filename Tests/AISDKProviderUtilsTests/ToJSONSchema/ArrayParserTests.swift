import Testing
@testable import AISDKZodAdapter

@Suite("Array Parser")
struct ArrayParserTests {
    @Test("simple array")
    func simpleArray() throws {
        let schema = parseArrayDef(
            TestZod.array(of: TestZod.string())._def as! ZodArrayDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("array"),
            "items": .object(["type": .string("string")])
        ])
    }

    @Test("array with any items")
    func arrayAnyItems() throws {
        let schema = parseArrayDef(
            TestZod.array(of: TestZod.any())._def as! ZodArrayDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("array")
        ])
    }

    @Test("array min and max")
    func arrayMinMax() throws {
        let schema = parseArrayDef(
            TestZod.array(of: TestZod.string(), min: 2, max: 4)._def as! ZodArrayDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "minItems": .number(2),
            "maxItems": .number(4)
        ])
    }

    @Test("array exact length")
    func arrayExactLength() throws {
        let schema = parseArrayDef(
            TestZod.array(of: TestZod.string(), exact: 5)._def as! ZodArrayDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("array"),
            "items": .object(["type": .string("string")]),
            "minItems": .number(5),
            "maxItems": .number(5)
        ])
    }

    @Test("array nonempty")
    func arrayNonEmpty() throws {
        let schema = parseArrayDef(
            TestZod.array(of: TestZod.any(), min: 1)._def as! ZodArrayDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("array"),
            "minItems": .number(1)
        ])
    }

    @Test("array references items")
    func arrayReferencesItems() throws {
        let objectSchema = TestZod.object([
            "hello": TestZod.string()
        ], unknownKeys: .strict)

        let unionSchema = TestZod.union([objectSchema, objectSchema])
        let arraySchema = TestZod.array(of: unionSchema)

        let schema = parseArrayDef(
            arraySchema._def as! ZodArrayDef,
            SchemaTestHelpers.refs()
        )

        SchemaTestHelpers.expect(schema, equals: [
            "type": .string("array"),
            "items": .object([
                "anyOf": .array([
                    .object([
                        "type": .string("object"),
                        "properties": .object([
                            "hello": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("hello")]),
                        "additionalProperties": .bool(false)
                    ]),
                    .object([
                        "$ref": .string("#/items/anyOf/0")
                    ])
                ])
            ])
        ])
    }
}

import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("JSONSchemaValidator")
struct JSONSchemaValidatorTests {
    @Test("anyOf does not bypass type validation")
    func anyOfDoesNotBypassTypeValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "anyOf": .array([
                .object(["format": .string("uuid")])
            ])
        ])

        let validator = JSONSchemaValidator(schema: schema)
        #expect(!validator.validate(value: .number(1)).isEmpty)
    }

    @Test("supports type unions via type arrays")
    func typeArrayUnionValidation() async throws {
        let schema: JSONValue = .object([
            "type": .array([.string("string"), .string("null")])
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .string("hello")).isEmpty)
        #expect(validator.validate(value: .null).isEmpty)
        #expect(!validator.validate(value: .number(1)).isEmpty)
    }

    @Test("validates enum constraints")
    func enumValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "enum": .array([.string("a"), .string("b")])
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .string("a")).isEmpty)
        #expect(!validator.validate(value: .string("c")).isEmpty)
    }

    @Test("validates const constraints")
    func constValidation() async throws {
        let schema: JSONValue = .object([
            "const": .string("fixed")
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .string("fixed")).isEmpty)
        #expect(!validator.validate(value: .string("other")).isEmpty)
    }

    @Test("validates integer type")
    func integerTypeValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("integer")
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .number(1)).isEmpty)
        #expect(!validator.validate(value: .number(1.5)).isEmpty)
        #expect(!validator.validate(value: .string("1")).isEmpty)
    }

    @Test("validates array length constraints")
    func arrayLengthConstraints() async throws {
        let schema: JSONValue = .object([
            "type": .string("array"),
            "minItems": .number(2),
            "maxItems": .number(2),
            "items": .object(["type": .string("number")])
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .array([.number(1), .number(2)])).isEmpty)
        #expect(!validator.validate(value: .array([.number(1)])).isEmpty)
        #expect(!validator.validate(value: .array([.number(1), .number(2), .number(3)])).isEmpty)
    }

    @Test("validates string length and pattern constraints")
    func stringConstraints() async throws {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "minLength": .number(2),
            "maxLength": .number(3),
            "pattern": .string("^[a-z]+$")
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .string("ab")).isEmpty)
        #expect(!validator.validate(value: .string("a")).isEmpty)
        #expect(!validator.validate(value: .string("abcd")).isEmpty)
        #expect(!validator.validate(value: .string("A1")).isEmpty)
    }

    @Test("validates numeric bounds")
    func numericBoundsValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("number"),
            "minimum": .number(1),
            "maximum": .number(3),
            "exclusiveMinimum": .number(0),
            "exclusiveMaximum": .number(4)
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .number(2)).isEmpty)
        #expect(!validator.validate(value: .number(0)).isEmpty)
        #expect(!validator.validate(value: .number(4)).isEmpty)
    }

    @Test("validates tuple schemas via items array and additionalItems")
    func tupleValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("array"),
            "minItems": .number(2),
            "items": .array([
                .object(["type": .string("number")]),
                .object(["type": .string("string")])
            ]),
            "additionalItems": .bool(false)
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .array([.number(1), .string("ok")])).isEmpty)
        #expect(!validator.validate(value: .array([.number(1), .number(2)])).isEmpty)
        #expect(!validator.validate(value: .array([.number(1), .string("ok"), .string("extra")])).isEmpty)

        let restSchema: JSONValue = .object([
            "type": .string("array"),
            "minItems": .number(2),
            "items": .array([
                .object(["type": .string("number")]),
                .object(["type": .string("string")])
            ]),
            "additionalItems": .object(["type": .string("number")])
        ])

        let restValidator = JSONSchemaValidator(schema: restSchema)
        #expect(restValidator.validate(value: .array([.number(1), .string("ok"), .number(3)])).isEmpty)
        #expect(!restValidator.validate(value: .array([.number(1), .string("ok"), .string("bad")])).isEmpty)
    }

    @Test("validates uniqueItems constraint")
    func uniqueItemsValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("array"),
            "uniqueItems": .bool(true)
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .array([.number(1), .number(2)])).isEmpty)
        #expect(!validator.validate(value: .array([.number(1), .number(1)])).isEmpty)
    }

    @Test("validates multipleOf constraint")
    func multipleOfValidation() async throws {
        let schema: JSONValue = .object([
            "type": .string("number"),
            "multipleOf": .number(2)
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .number(4)).isEmpty)
        #expect(!validator.validate(value: .number(3)).isEmpty)
    }

    @Test("validates object minProperties/maxProperties constraints")
    func objectPropertiesBounds() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "minProperties": .number(2),
            "maxProperties": .number(2)
        ])

        let validator = JSONSchemaValidator(schema: schema)

        #expect(validator.validate(value: .object(["a": .string("1"), "b": .string("2")])).isEmpty)
        #expect(!validator.validate(value: .object(["a": .string("1")])).isEmpty)
        #expect(!validator.validate(value: .object(["a": .string("1"), "b": .string("2"), "c": .string("3")])).isEmpty)
    }
}

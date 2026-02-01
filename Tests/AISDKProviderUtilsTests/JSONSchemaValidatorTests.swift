import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("JSONSchemaValidator")
struct JSONSchemaValidatorTests {
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
}


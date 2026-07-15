import Testing
@testable import AnthropicProvider
import AISDKProvider

@Suite("Anthropic JSON Schema sanitization")
struct AnthropicSanitizeJSONSchemaTests {
    @Test("moves unsupported number constraints into descriptions")
    func numberConstraints() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "recurringIntervalMinutes": .object([
                    "type": .string("number"),
                    "exclusiveMinimum": .number(0),
                    "minimum": .number(1),
                    "maximum": .number(60),
                    "exclusiveMaximum": .number(120),
                ])
            ]),
            "required": .array([.string("recurringIntervalMinutes")]),
            "additionalProperties": .bool(true),
        ])

        #expect(sanitizeAnthropicJSONSchema(schema) == .object([
            "type": .string("object"),
            "properties": .object([
                "recurringIntervalMinutes": .object([
                    "type": .string("number"),
                    "description": .string(
                        "minimum: 1; maximum: 60; exclusive minimum: 0; exclusive maximum: 120."
                    ),
                ])
            ]),
            "required": .array([.string("recurringIntervalMinutes")]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("moves unsupported string constraints and formats into descriptions")
    func stringConstraints() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "description": .string("A URL slug"),
            "minLength": .number(1),
            "maxLength": .number(20),
            "pattern": .string("^[a-z0-9-]+$"),
            "format": .string("regex"),
        ])

        #expect(sanitizeAnthropicJSONSchema(schema) == .object([
            "type": .string("string"),
            "description": .string(
                "A URL slug\nmin length: 1; max length: 20; pattern: ^[a-z0-9-]+$; format: regex."
            ),
        ]))
    }

    @Test("recursively sanitizes arrays, definitions, and compositions")
    func recursiveSchemas() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "$defs": .object([
                "PositiveInteger": .object([
                    "type": .string("integer"),
                    "minimum": .number(1),
                ])
            ]),
            "properties": .object([
                "count": .object(["$ref": .string("#/$defs/PositiveInteger")]),
                "tags": .object([
                    "type": .string("array"),
                    "minItems": .number(2),
                    "maxItems": .number(4),
                    "uniqueItems": .bool(true),
                    "items": .object([
                        "anyOf": .array([
                            .object(["type": .string("string"), "minLength": .number(1)]),
                            .object(["type": .string("number"), "maximum": .number(10)]),
                        ])
                    ]),
                ]),
            ]),
        ])

        #expect(sanitizeAnthropicJSONSchema(schema) == .object([
            "type": .string("object"),
            "$defs": .object([
                "PositiveInteger": .object([
                    "type": .string("integer"),
                    "description": .string("minimum: 1."),
                ])
            ]),
            "properties": .object([
                "count": .object(["$ref": .string("#/$defs/PositiveInteger")]),
                "tags": .object([
                    "type": .string("array"),
                    "description": .string("min items: 2; max items: 4; unique items: true."),
                    "items": .object([
                        "anyOf": .array([
                            .object([
                                "type": .string("string"),
                                "description": .string("min length: 1."),
                            ]),
                            .object([
                                "type": .string("number"),
                                "description": .string("maximum: 10."),
                            ]),
                        ])
                    ]),
                ]),
            ]),
            "additionalProperties": .bool(false),
        ]))
    }

    @Test("converts oneOf to anyOf")
    func convertsOneOf() {
        let schema: JSONValue = .object([
            "oneOf": .array([
                .object(["type": .string("string"), "minLength": .number(1)]),
                .object(["type": .string("number"), "minimum": .number(0)]),
            ])
        ])

        #expect(sanitizeAnthropicJSONSchema(schema) == .object([
            "anyOf": .array([
                .object([
                    "type": .string("string"),
                    "description": .string("min length: 1."),
                ]),
                .object([
                    "type": .string("number"),
                    "description": .string("minimum: 0."),
                ]),
            ])
        ]))
    }

    @Test("does not mutate the input schema")
    func preservesInput() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "value": .object([
                    "type": .string("number"),
                    "exclusiveMinimum": .number(0),
                ])
            ]),
        ])

        _ = sanitizeAnthropicJSONSchema(schema)

        #expect(schema == .object([
            "type": .string("object"),
            "properties": .object([
                "value": .object([
                    "type": .string("number"),
                    "exclusiveMinimum": .number(0),
                ])
            ]),
        ]))
    }
}

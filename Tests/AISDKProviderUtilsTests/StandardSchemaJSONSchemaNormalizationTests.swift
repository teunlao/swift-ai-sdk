import Testing

@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("standardSchema JSON Schema normalization")
struct StandardSchemaJSONSchemaNormalizationTests {
    @Test("adds additionalProperties false to objects recursively")
    func addsAdditionalPropertiesFalseToObjectsRecursively() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "user": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": .string("string")])
                    ])
                ]),
                "age": .object(["type": .string("number")])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "user": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "name": .object(["type": .string("string")])
                    ])
                ]),
                "age": .object(["type": .string("number")])
            ])
        ]))
    }

    @Test("adds additionalProperties false to objects inside arrays")
    func addsAdditionalPropertiesFalseToObjectsInsideArrays() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "ingredients": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "amount": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("name"), .string("amount")])
                    ])
                ])
            ]),
            "required": .array([.string("ingredients")])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "ingredients": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "additionalProperties": .bool(false),
                        "properties": .object([
                            "name": .object(["type": .string("string")]),
                            "amount": .object(["type": .string("string")])
                        ]),
                        "required": .array([.string("name"), .string("amount")])
                    ])
                ])
            ]),
            "required": .array([.string("ingredients")])
        ]))
    }

    @Test("adds additionalProperties false when type union includes object")
    func addsAdditionalPropertiesFalseWhenTypeUnionIncludesObject() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "response": .object([
                    "type": .array([.string("object"), .string("null")]),
                    "properties": .object([
                        "name": .object(["type": .string("string")])
                    ])
                ])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "response": .object([
                    "type": .array([.string("object"), .string("null")]),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "name": .object(["type": .string("string")])
                    ])
                ])
            ])
        ]))
    }

    @Test("adds additionalProperties false to objects inside anyOf")
    func addsAdditionalPropertiesFalseToObjectsInsideAnyOf() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "response": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object(["type": .string("string")])
                            ])
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "amount": .object(["type": .string("string")])
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "response": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "name": .object(["type": .string("string")])
                            ])
                        ]),
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "amount": .object(["type": .string("string")])
                            ])
                        ])
                    ])
                ])
            ])
        ]))
    }

    @Test("adds additionalProperties false to objects inside allOf")
    func addsAdditionalPropertiesFalseToObjectsInsideAllOf() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "response": .object([
                    "allOf": .array([
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "name": .object(["type": .string("string")])
                            ])
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "age": .object(["type": .string("number")])
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "response": .object([
                    "allOf": .array([
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "name": .object(["type": .string("string")])
                            ])
                        ]),
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "age": .object(["type": .string("number")])
                            ])
                        ])
                    ])
                ])
            ])
        ]))
    }

    @Test("adds additionalProperties false to objects inside oneOf")
    func addsAdditionalPropertiesFalseToObjectsInsideOneOf() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "response": .object([
                    "oneOf": .array([
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "success": .object(["type": .string("boolean")])
                            ])
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "error": .object(["type": .string("string")])
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "response": .object([
                    "oneOf": .array([
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "success": .object(["type": .string("boolean")])
                            ])
                        ]),
                        .object([
                            "type": .string("object"),
                            "additionalProperties": .bool(false),
                            "properties": .object([
                                "error": .object(["type": .string("string")])
                            ])
                        ])
                    ])
                ])
            ])
        ]))
    }

    @Test("adds additionalProperties false to object schemas inside definitions")
    func addsAdditionalPropertiesFalseToObjectsInsideDefinitions() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "node": .object(["$ref": .string("#/definitions/Node")])
            ]),
            "definitions": .object([
                "Node": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["type": .string("string")]),
                        "next": .object(["$ref": .string("#/definitions/Node")])
                    ])
                ])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "node": .object(["$ref": .string("#/definitions/Node")])
            ]),
            "definitions": .object([
                "Node": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "value": .object(["type": .string("string")]),
                        "next": .object(["$ref": .string("#/definitions/Node")])
                    ])
                ])
            ])
        ]))
    }

    @Test("overwrites existing additionalProperties flags")
    func overwritesExistingAdditionalPropertiesFlags() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "additionalProperties": .bool(true),
            "properties": .object([
                "meta": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(true),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "meta": .object([
                    "type": .string("object"),
                    "additionalProperties": .bool(false),
                    "properties": .object([
                        "id": .object(["type": .string("string")])
                    ])
                ])
            ])
        ]))
    }

    @Test("leaves non-object schemas unchanged")
    func leavesNonObjectSchemasUnchanged() async throws {
        let schema: JSONValue = .object([
            "type": .string("string")
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == schema)
    }

    @Test("preserves boolean JSON Schema definitions")
    func preservesBooleanJSONSchemaDefinitions() async throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "accepted": .bool(true),
                "rejected": .bool(false)
            ])
        ])

        let result = try await normalizedJSONSchema(schema)

        #expect(result == .object([
            "type": .string("object"),
            "additionalProperties": .bool(false),
            "properties": .object([
                "accepted": .bool(true),
                "rejected": .bool(false)
            ])
        ]))
    }

    private func normalizedJSONSchema(_ jsonSchema: JSONValue) async throws -> JSONValue {
        let definition = StandardSchemaV1<JSONValue>.Definition(
            vendor: "custom",
            jsonSchema: { jsonSchema },
            validate: { _ in .value(.null) }
        )

        return try await standardSchema(StandardSchemaV1(definition: definition)).jsonSchema()
    }
}

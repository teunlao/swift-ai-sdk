import Foundation
import Testing
@testable import AISDKProvider
@testable import GoogleProvider

@Suite("convertJSONSchemaToOpenAPISchema")
struct ConvertJSONSchemaToOpenAPISchemaTests {
    @Test("returns nil for empty object schema")
    func emptyObjectSchema() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([:])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema)
        #expect(result == nil)
    }

    @Test("copies description and type values")
    func preservesDescriptionAndType() throws {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "description": .string("An identifier")
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["type"] as? String == "string")
        #expect(result?["description"] as? String == "An identifier")
    }

    @Test("marks nullable enums that include null")
    func nullableEnum() throws {
        let schema: JSONValue = .object([
            "type": .array([
                .string("string"),
                .string("null")
            ]),
            "enum": .array([
                .string("a"),
                .string("b")
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["type"] as? String == "string")
        #expect(result?["nullable"] as? Bool == true)
        if let values = result?["enum"] as? [String] {
            #expect(values == ["a", "b"])
        } else {
            Issue.record("Expected enum array")
        }
    }

    @Test("handles array item schemas")
    func arrayItems() throws {
        let schema: JSONValue = .object([
            "type": .string("array"),
            "items": .object([
                "type": .string("number"),
                "format": .string("float")
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["type"] as? String == "array")
        let items = result?["items"] as? [String: Any]
        #expect(items?["type"] as? String == "number")
        #expect(items?["format"] as? String == "float")
    }

    @Test("should remove additionalProperties and $schema")
    func removeAdditionalPropertiesAndSchema() throws {
        let schema: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "age": .object(["type": .string("number")])
            ]),
            "additionalProperties": .bool(false)
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["$schema"] == nil)
        #expect(result?["additionalProperties"] == nil)
        #expect(result?["type"] as? String == "object")
        #expect(result?["properties"] != nil)
    }

    @Test("should remove additionalProperties object from nested object schemas")
    func removeAdditionalPropertiesFromNested() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "keys": .object([
                    "type": .string("object"),
                    "additionalProperties": .object(["type": .string("string")]),
                    "description": .string("Description for the key")
                ])
            ]),
            "additionalProperties": .bool(false)
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        let keys = props?["keys"] as? [String: Any]
        #expect(keys?["additionalProperties"] == nil)
        #expect(keys?["description"] as? String == "Description for the key")
    }

    @Test("should handle nested objects and arrays")
    func handleNestedObjectsAndArrays() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "users": .object([
                    "type": .string("array"),
                    "items": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "id": .object(["type": .string("number")]),
                            "name": .object(["type": .string("string")])
                        ]),
                        "additionalProperties": .bool(false)
                    ])
                ])
            ]),
            "additionalProperties": .bool(false)
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["additionalProperties"] == nil)
        let props = result?["properties"] as? [String: Any]
        let users = props?["users"] as? [String: Any]
        let items = users?["items"] as? [String: Any]
        #expect(items?["additionalProperties"] == nil)
    }

    @Test("should convert const to enum with a single value")
    func convertConstToEnum() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "status": .object(["const": .string("active")])
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        let status = props?["status"] as? [String: Any]
        let enumValues = status?["enum"] as? [String]
        #expect(enumValues == ["active"])
    }

    @Test("should handle allOf, anyOf, and oneOf")
    func handleCombinators() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "allOfProp": .object(["allOf": .array([
                    .object(["type": .string("string")]),
                    .object(["minLength": .number(5)])
                ])]),
                "anyOfProp": .object(["anyOf": .array([
                    .object(["type": .string("string")]),
                    .object(["type": .string("number")])
                ])])
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        #expect((props?["allOfProp"] as? [String: Any])?["allOf"] != nil)
        #expect((props?["anyOfProp"] as? [String: Any])?["anyOf"] != nil)
    }

    @Test("should convert format: date-time correctly")
    func convertDateTimeFormat() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "timestamp": .object([
                    "type": .string("string"),
                    "format": .string("date-time")
                ])
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        let timestamp = props?["timestamp"] as? [String: Any]
        #expect(timestamp?["format"] as? String == "date-time")
    }

    @Test("should handle required properties")
    func handleRequiredProperties() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("number")]),
                "name": .object(["type": .string("string")])
            ]),
            "required": .array([.string("id")])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let required = result?["required"] as? [String]
        #expect(required == ["id"])
    }

    @Test("should convert deeply nested const to enum")
    func deeplyNestedConst() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "nested": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "value": .object(["const": .string("specific value")])
                    ])
                ])
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        let nested = props?["nested"] as? [String: Any]
        let nestedProps = nested?["properties"] as? [String: Any]
        let value = nestedProps?["value"] as? [String: Any]
        let enumValues = value?["enum"] as? [String]
        #expect(enumValues == ["specific value"])
    }

    @Test("should handle null type correctly")
    func handleNullType() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "nullableField": .object(["type": .array([.string("string"), .string("null")])])
            ])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        let nullable = props?["nullableField"] as? [String: Any]
        #expect(nullable?["type"] as? String == "string")
        #expect(nullable?["nullable"] as? Bool == true)
    }

    @Test("should convert string enum properties")
    func convertStringEnum() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array([.string("text"), .string("code"), .string("image")])
                ])
            ]),
            "required": .array([.string("kind")]),
            "additionalProperties": .bool(false)
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["additionalProperties"] == nil)
        let props = result?["properties"] as? [String: Any]
        let kind = props?["kind"] as? [String: Any]
        let enumValues = kind?["enum"] as? [String]
        #expect(enumValues == ["text", "code", "image"])
    }

    @Test("should convert nullable string enum")
    func convertNullableStringEnum() throws {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "fieldD": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("string"),
                            "enum": .array([.string("a"), .string("b"), .string("c")])
                        ]),
                        .object(["type": .string("null")])
                    ])
                ])
            ]),
            "required": .array([.string("fieldD")])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        let props = result?["properties"] as? [String: Any]
        let fieldD = props?["fieldD"] as? [String: Any]
        #expect(fieldD?["nullable"] as? Bool == true)
        #expect(fieldD?["type"] as? String == "string")
        let enumValues = fieldD?["enum"] as? [String]
        #expect(enumValues == ["a", "b", "c"])
    }
}

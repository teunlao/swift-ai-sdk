import Foundation
import Testing
@testable import AISDKProvider
@testable import GoogleProvider

@Suite("convertJSONSchemaToOpenAPISchema")
struct ConvertJSONSchemaToOpenAPISchemaTests {
    @Test("returns nil for empty object schema")
    func emptyObjectSchema() {
        let schema: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([:])
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema)
        #expect(result == nil)
    }

    @Test("copies description and type values")
    func preservesDescriptionAndType() {
        let schema: JSONValue = .object([
            "type": .string("string"),
            "description": .string("An identifier")
        ])

        let result = convertJSONSchemaToOpenAPISchema(schema) as? [String: Any]
        #expect(result?["type"] as? String == "string")
        #expect(result?["description"] as? String == "An identifier")
    }

    @Test("marks nullable enums that include null")
    func nullableEnum() {
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
    func arrayItems() {
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
}

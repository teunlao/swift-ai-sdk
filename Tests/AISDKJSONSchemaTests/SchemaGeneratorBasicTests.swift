import Testing
import AISDKJSONSchema
import AISDKProviderUtils

private enum TestSchemas {
    struct Person: Codable, Sendable {
        let name: String
        let age: Int?
    }

    struct Catalog: Codable, Sendable {
        struct Item: Codable, Sendable {
            let id: Int
            let tags: [String]
        }

        let items: [Item]
    }
}

@Test("auto schema produces object with properties and required list")
func basicObjectSchema() async throws {
    let schema = JSONSchemaGenerator.generate(for: TestSchemas.Person.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema, got \(schema)")
        return
    }

    guard case let .object(properties) = root["properties"] else {
        Issue.record("Missing properties in schema")
        return
    }

    #expect(properties["name"] != nil)
    #expect(properties["age"] != nil)

    if case let .array(required) = root["required"] {
        let names = required.compactMap { value -> String? in
            guard case let .string(name) = value else { return nil }
            return name
        }
        #expect(names.contains("name"))
        #expect(!names.contains("age"))
    } else {
        Issue.record("Missing required list")
    }
}

@Test("nested arrays and objects receive item schema",
      .disabled("TODO: add once array/object schema generation is finalized"))
func nestedArraySchema() async throws {
    // Placeholder: exercise generator to ensure call does not trap.
    _ = JSONSchemaGenerator.generate(for: TestSchemas.Catalog.self)
}

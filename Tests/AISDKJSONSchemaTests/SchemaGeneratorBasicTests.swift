import Foundation
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

@Test("nested arrays and objects receive item schema")
func nestedArraySchema() async throws {
    let schema = JSONSchemaGenerator.generate(for: TestSchemas.Catalog.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema")
        return
    }

    guard case let .object(properties) = root["properties"],
          case let .object(itemsSchema) = properties["items"],
          case let .object(itemSchema) = itemsSchema["items"],
          case let .object(itemProps) = itemSchema["properties"],
          case let .object(tagsSchema) = itemProps["tags"],
          case let .object(tagItemsSchema) = tagsSchema["items"] else {
        Issue.record("Unexpected nested structure: \(schema)")
        return
    }

    #expect(itemProps["id"] != nil)
    #expect(tagItemsSchema["type"] == .string("string"))
}

@Test("schema handles optional fields correctly")
func optionalFieldsSchema() async throws {
    struct WithOptionals: Codable, Sendable {
        let required: String
        let optional: String?
    }

    let schema = JSONSchemaGenerator.generate(for: WithOptionals.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema")
        return
    }

    guard case let .array(required) = root["required"] else {
        Issue.record("Missing required list")
        return
    }

    let requiredNames = required.compactMap { value -> String? in
        guard case let .string(name) = value else { return nil }
        return name
    }

    #expect(requiredNames.contains("required"))
    #expect(!requiredNames.contains("optional"))
}

@Test("schema handles primitive types")
func primitiveTypesSchema() async throws {
    struct Primitives: Codable, Sendable {
        let string: String
        let int: Int
        let double: Double
        let bool: Bool
    }

    let schema = JSONSchemaGenerator.generate(for: Primitives.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(stringType) = properties["string"],
          case let .object(intType) = properties["int"],
          case let .object(doubleType) = properties["double"],
          case let .object(boolType) = properties["bool"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(stringType["type"] == .string("string"))
    #expect(intType["type"] == .string("integer"))
    #expect(doubleType["type"] == .string("number"))
    #expect(boolType["type"] == .string("boolean"))
}

@Test("schema handles array of primitives")
func arrayPrimitivesSchema() async throws {
    struct WithArrays: Codable, Sendable {
        let strings: [String]
        let numbers: [Int]
    }

    let schema = JSONSchemaGenerator.generate(for: WithArrays.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(stringsType) = properties["strings"],
          case let .object(numbersType) = properties["numbers"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(stringsType["type"] == .string("array"))
    #expect(numbersType["type"] == .string("array"))

    guard case let .object(stringItems) = stringsType["items"],
          case let .object(numberItems) = numbersType["items"] else {
        Issue.record("Missing array items schema")
        return
    }

    #expect(stringItems["type"] == .string("string"))
    #expect(numberItems["type"] == .string("integer"))
}

@Test("schema handles deeply nested structures")
func deeplyNestedSchema() async throws {
    struct Level3: Codable, Sendable {
        let value: String
    }

    struct Level2: Codable, Sendable {
        let level3: Level3
    }

    struct Level1: Codable, Sendable {
        let level2: Level2
    }

    let schema = JSONSchemaGenerator.generate(for: Level1.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema, got: \(schema)")
        return
    }

    guard case let .object(properties) = root["properties"] else {
        Issue.record("Missing properties, got root: \(root)")
        return
    }

    guard case let .object(level2Schema) = properties["level2"] else {
        Issue.record("Missing level2, got properties: \(properties)")
        return
    }

    guard case let .object(level2Props) = level2Schema["properties"] else {
        Issue.record("Missing level2 properties, got level2Schema: \(level2Schema)")
        return
    }

    guard case let .object(level3Schema) = level2Props["level3"] else {
        Issue.record("Missing level3, got level2Props: \(level2Props)")
        return
    }

    guard case let .object(level3Props) = level3Schema["properties"] else {
        Issue.record("Missing level3 properties, got level3Schema: \(level3Schema)")
        return
    }

    #expect(level3Props["value"] != nil)
}

@Test("FlexibleSchema.auto integration")
func autoSchemaIntegration() async throws {
    struct User: Codable, Sendable {
        let id: Int
        let name: String
        let email: String?
    }

    // Should create schema without throwing
    _ = FlexibleSchema.auto(User.self)
}

@Test("array of nested objects")
func arrayOfNestedObjects() async throws {
    struct Tag: Codable, Sendable {
        let name: String
        let color: String
    }

    struct Post: Codable, Sendable {
        let title: String
        let tags: [Tag]
    }

    let schema = JSONSchemaGenerator.generate(for: Post.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(tagsSchema) = properties["tags"],
          case let .object(tagItems) = tagsSchema["items"],
          case let .object(tagProps) = tagItems["properties"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(tagsSchema["type"] == .string("array"))
    #expect(tagProps["name"] != nil)
    #expect(tagProps["color"] != nil)
}

@Test("multiple levels of nested arrays")
func multiLevelArrays() async throws {
    struct Comment: Codable, Sendable {
        let text: String
    }

    struct Thread: Codable, Sendable {
        let comments: [Comment]
    }

    struct Forum: Codable, Sendable {
        let threads: [Thread]
    }

    let schema = JSONSchemaGenerator.generate(for: Forum.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(threadsSchema) = properties["threads"],
          case let .object(threadItem) = threadsSchema["items"],
          case let .object(threadProps) = threadItem["properties"],
          case let .object(commentsSchema) = threadProps["comments"] else {
        Issue.record("Unexpected nested array structure")
        return
    }

    #expect(threadsSchema["type"] == .string("array"))
    #expect(commentsSchema["type"] == .string("array"))

    // Check comment items
    guard case let .object(commentItem) = commentsSchema["items"],
          case let .object(commentProps) = commentItem["properties"] else {
        Issue.record("Missing comment item schema")
        return
    }

    #expect(commentProps["text"] != nil)
}

@Test("mixed optional and required nested fields")
func mixedOptionalNested() async throws {
    struct Address: Codable, Sendable {
        let street: String
        let city: String
        let zip: String?
    }

    struct Person: Codable, Sendable {
        let name: String
        let age: Int?
        let address: Address?
    }

    let schema = JSONSchemaGenerator.generate(for: Person.self)

    guard case let .object(root) = schema,
          case let .array(required) = root["required"] else {
        Issue.record("Missing required list")
        return
    }

    let requiredNames = required.compactMap { value -> String? in
        guard case let .string(name) = value else { return nil }
        return name
    }

    #expect(requiredNames.contains("name"))
    #expect(!requiredNames.contains("age"))
    #expect(!requiredNames.contains("address"))
}

@Test("all numeric types")
func allNumericTypes() async throws {
    struct Numbers: Codable, Sendable {
        let int: Int
        let int8: Int8
        let int16: Int16
        let int32: Int32
        let int64: Int64
        let uint: UInt
        let uint8: UInt8
        let uint16: UInt16
        let uint32: UInt32
        let uint64: UInt64
        let double: Double
        let float: Float
    }

    let schema = JSONSchemaGenerator.generate(for: Numbers.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    // All integer types should be "integer"
    for key in ["int", "int8", "int16", "int32", "int64", "uint", "uint8", "uint16", "uint32", "uint64"] {
        guard case let .object(typeSchema) = properties[key] else {
            Issue.record("Missing property: \(key)")
            continue
        }
        #expect(typeSchema["type"] == .string("integer"), "Property \(key) should be integer")
    }

    // Float/Double should be "number"
    for key in ["double", "float"] {
        guard case let .object(typeSchema) = properties[key] else {
            Issue.record("Missing property: \(key)")
            continue
        }
        #expect(typeSchema["type"] == .string("number"), "Property \(key) should be number")
    }
}

@Test("array of arrays")
func arrayOfArrays() async throws {
    struct Matrix: Codable, Sendable {
        let rows: [[Int]]
    }

    let schema = JSONSchemaGenerator.generate(for: Matrix.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(rowsSchema) = properties["rows"],
          case let .object(innerArray) = rowsSchema["items"],
          case let .object(intSchema) = innerArray["items"] else {
        Issue.record("Unexpected array of arrays structure")
        return
    }

    #expect(rowsSchema["type"] == .string("array"))
    #expect(innerArray["type"] == .string("array"))
    #expect(intSchema["type"] == .string("integer"))
}

@Test("complex real-world structure")
func complexRealWorld() async throws {
    struct Author: Codable, Sendable {
        let id: Int
        let name: String
        let email: String?
    }

    struct Comment: Codable, Sendable {
        let id: Int
        let text: String
        let author: Author
        let timestamp: Double
    }

    struct BlogPost: Codable, Sendable {
        let id: Int
        let title: String
        let content: String
        let author: Author
        let tags: [String]
        let comments: [Comment]
        let published: Bool
        let views: Int?
    }

    let schema = JSONSchemaGenerator.generate(for: BlogPost.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .array(required) = root["required"] else {
        Issue.record("Invalid schema structure")
        return
    }

    let requiredNames = required.compactMap { value -> String? in
        guard case let .string(name) = value else { return nil }
        return name
    }

    // Check required fields
    #expect(requiredNames.contains("id"))
    #expect(requiredNames.contains("title"))
    #expect(requiredNames.contains("author"))
    #expect(!requiredNames.contains("views")) // optional

    // Check author nested object
    guard case let .object(authorSchema) = properties["author"],
          case let .object(authorProps) = authorSchema["properties"] else {
        Issue.record("Missing author schema")
        return
    }

    #expect(authorProps["id"] != nil)
    #expect(authorProps["name"] != nil)

    // Check tags array
    guard case let .object(tagsSchema) = properties["tags"],
          case let .object(tagItems) = tagsSchema["items"] else {
        Issue.record("Missing tags schema")
        return
    }

    #expect(tagsSchema["type"] == .string("array"))
    #expect(tagItems["type"] == .string("string"))

    // Check comments array with nested author
    guard case let .object(commentsSchema) = properties["comments"],
          case let .object(commentItem) = commentsSchema["items"],
          case let .object(commentProps) = commentItem["properties"],
          case let .object(commentAuthor) = commentProps["author"] else {
        Issue.record("Missing comments schema")
        return
    }

    #expect(commentsSchema["type"] == .string("array"))
    #expect(commentProps["text"] != nil)
    #expect(commentAuthor["properties"] != nil)
}

@Test("empty object")
func emptyObject() async throws {
    struct Empty: Codable, Sendable {}

    let schema = JSONSchemaGenerator.generate(for: Empty.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema")
        return
    }

    #expect(root["type"] == .string("object"))

    // Should have empty properties
    if case let .object(properties) = root["properties"] {
        #expect(properties.isEmpty)
    }
}

@Test("only optional fields")
func onlyOptionalFields() async throws {
    struct AllOptional: Codable, Sendable {
        let field1: String?
        let field2: Int?
        let field3: Bool?
    }

    let schema = JSONSchemaGenerator.generate(for: AllOptional.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema")
        return
    }

    // Required list should be empty or missing
    if case let .array(required) = root["required"] {
        #expect(required.isEmpty, "All fields are optional, required should be empty")
    }
}

@Test("mixed primitives and nested objects in array")
func mixedArrayContent() async throws {
    struct Item: Codable, Sendable {
        let name: String
        let quantity: Int
    }

    struct Inventory: Codable, Sendable {
        let items: [Item]
        let tags: [String]
        let counts: [Int]
    }

    let schema = JSONSchemaGenerator.generate(for: Inventory.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(itemsSchema) = properties["items"],
          case let .object(tagsSchema) = properties["tags"],
          case let .object(countsSchema) = properties["counts"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    // Items array should have object items
    guard case let .object(itemSchema) = itemsSchema["items"],
          case let .object(itemProps) = itemSchema["properties"] else {
        Issue.record("Items should be objects")
        return
    }

    #expect(itemProps["name"] != nil)
    #expect(itemProps["quantity"] != nil)

    // Tags should be string array
    guard case let .object(tagItem) = tagsSchema["items"] else {
        Issue.record("Tags should have items")
        return
    }
    #expect(tagItem["type"] == .string("string"))

    // Counts should be integer array
    guard case let .object(countItem) = countsSchema["items"] else {
        Issue.record("Counts should have items")
        return
    }
    #expect(countItem["type"] == .string("integer"))
}

@Test("deeply nested optional chain")
func deeplyNestedOptionals() async throws {
    struct Level4: Codable, Sendable {
        let value: String
    }

    struct Level3: Codable, Sendable {
        let level4: Level4?
    }

    struct Level2: Codable, Sendable {
        let level3: Level3?
    }

    struct Level1: Codable, Sendable {
        let level2: Level2?
    }

    let schema = JSONSchemaGenerator.generate(for: Level1.self)

    guard case let .object(root) = schema else {
        Issue.record("Expected object schema")
        return
    }

    // Check that level2 is not in required (it's optional)
    if case let .array(required) = root["required"] {
        let requiredNames = required.compactMap { value -> String? in
            guard case let .string(name) = value else { return nil }
            return name
        }
        #expect(!requiredNames.contains("level2"))
    }

    // If no required list, that's also fine (all fields optional)
}

@Test("large object with many fields")
func largeObject() async throws {
    struct LargeStruct: Codable, Sendable {
        let field01: String
        let field02: Int
        let field03: Double
        let field04: Bool
        let field05: String?
        let field06: Int
        let field07: Double
        let field08: Bool
        let field09: String
        let field10: Int?
        let field11: [String]
        let field12: [Int]
        let field13: String
        let field14: Int
        let field15: Bool
    }

    let schema = JSONSchemaGenerator.generate(for: LargeStruct.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .array(required) = root["required"] else {
        Issue.record("Invalid large object schema")
        return
    }

    // Should have all 15 properties
    #expect(properties.count == 15)

    let requiredNames = required.compactMap { value -> String? in
        guard case let .string(name) = value else { return nil }
        return name
    }

    // Should have 13 required fields (field05 and field10 are optional)
    #expect(requiredNames.count == 13)
    #expect(!requiredNames.contains("field05"))
    #expect(!requiredNames.contains("field10"))
}

@Test("three level nested arrays with objects")
func threeLevelNestedArrays() async throws {
    struct Item: Codable, Sendable {
        let name: String
    }

    struct Container: Codable, Sendable {
        let items: [[Item]]
    }

    let schema = JSONSchemaGenerator.generate(for: Container.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(itemsSchema) = properties["items"],
          case let .object(level1Array) = itemsSchema["items"],
          case let .object(level2Item) = level1Array["items"],
          case let .object(itemProps) = level2Item["properties"] else {
        Issue.record("Unexpected three-level array structure")
        return
    }

    #expect(itemsSchema["type"] == .string("array"))
    #expect(level1Array["type"] == .string("array"))
    #expect(itemProps["name"] != nil)
}

@Test("Foundation types: Date, URL, Data")
func foundationTypes() async throws {
    struct WithFoundation: Codable, Sendable {
        let createdAt: Date
        let website: URL
        let avatar: Data
    }

    let schema = JSONSchemaGenerator.generate(for: WithFoundation.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(dateSchema) = properties["createdAt"],
          case let .object(urlSchema) = properties["website"],
          case let .object(dataSchema) = properties["avatar"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    // Date should be string with date-time format
    #expect(dateSchema["type"] == .string("string"))
    #expect(dateSchema["format"] == .string("date-time"))

    // URL should be string with uri format
    #expect(urlSchema["type"] == .string("string"))
    #expect(urlSchema["format"] == .string("uri"))

    // Data should be string with binary format
    #expect(dataSchema["type"] == .string("string"))
    #expect(dataSchema["format"] == .string("binary"))
}

@Test("Decimal type support")
func decimalType() async throws {
    struct WithDecimal: Codable, Sendable {
        let price: Decimal
        let tax: Decimal
    }

    let schema = JSONSchemaGenerator.generate(for: WithDecimal.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(priceSchema) = properties["price"],
          case let .object(taxSchema) = properties["tax"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(priceSchema["type"] == .string("number"))
    #expect(taxSchema["type"] == .string("number"))
}

@Test("String enum with CaseIterable")
func stringEnum() async throws {
    enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case approved
        case rejected
    }

    struct Task: Codable, Sendable {
        let status: Status
    }

    let schema = JSONSchemaGenerator.generate(for: Task.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(statusSchema) = properties["status"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(statusSchema["type"] == .string("string"))

    // Check enum values
    guard case let .array(enumValues) = statusSchema["enum"] else {
        Issue.record("Missing enum values")
        return
    }

    let stringValues = enumValues.compactMap { value -> String? in
        guard case let .string(s) = value else { return nil }
        return s
    }

    #expect(stringValues.contains("pending"))
    #expect(stringValues.contains("approved"))
    #expect(stringValues.contains("rejected"))
    #expect(stringValues.count == 3)
}

@Test("Integer enum with CaseIterable")
func integerEnum() async throws {
    enum Priority: Int, Codable, Sendable, CaseIterable {
        case low = 0
        case medium = 1
        case high = 2
    }

    struct Task: Codable, Sendable {
        let priority: Priority
    }

    let schema = JSONSchemaGenerator.generate(for: Task.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(prioritySchema) = properties["priority"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(prioritySchema["type"] == .string("integer"))

    // Check enum values
    guard case let .array(enumValues) = prioritySchema["enum"] else {
        Issue.record("Missing enum values")
        return
    }

    let intValues = enumValues.compactMap { value -> Int? in
        guard case let .number(n) = value else { return nil }
        return Int(n)
    }

    #expect(intValues.contains(0))
    #expect(intValues.contains(1))
    #expect(intValues.contains(2))
    #expect(intValues.count == 3)
}

@Test("Complex real-world with Date, URL, and enum")
func complexRealWorldWithFoundation() async throws {
    enum PostStatus: String, Codable, Sendable, CaseIterable {
        case draft
        case published
        case archived
    }

    struct Author: Codable, Sendable {
        let name: String
        let avatarUrl: URL
    }

    struct BlogPost: Codable, Sendable {
        let title: String
        let author: Author
        let status: PostStatus
        let createdAt: Date
        let updatedAt: Date?
        let coverImage: Data?
    }

    let schema = JSONSchemaGenerator.generate(for: BlogPost.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .array(required) = root["required"] else {
        Issue.record("Invalid schema structure")
        return
    }

    let requiredNames = required.compactMap { value -> String? in
        guard case let .string(name) = value else { return nil }
        return name
    }

    // Check required fields
    #expect(requiredNames.contains("title"))
    #expect(requiredNames.contains("author"))
    #expect(requiredNames.contains("status"))
    #expect(requiredNames.contains("createdAt"))
    #expect(!requiredNames.contains("updatedAt")) // optional
    #expect(!requiredNames.contains("coverImage")) // optional

    // Check author nested object with URL
    guard case let .object(authorSchema) = properties["author"],
          case let .object(authorProps) = authorSchema["properties"],
          case let .object(avatarUrlSchema) = authorProps["avatarUrl"] else {
        Issue.record("Missing author schema")
        return
    }

    #expect(avatarUrlSchema["type"] == .string("string"))
    #expect(avatarUrlSchema["format"] == .string("uri"))

    // Check status enum
    guard case let .object(statusSchema) = properties["status"],
          case let .array(statusEnum) = statusSchema["enum"] else {
        Issue.record("Missing status enum")
        return
    }

    let statusValues = statusEnum.compactMap { value -> String? in
        guard case let .string(s) = value else { return nil }
        return s
    }

    #expect(statusValues.contains("draft"))
    #expect(statusValues.contains("published"))
    #expect(statusValues.contains("archived"))

    // Check dates
    guard case let .object(createdAtSchema) = properties["createdAt"] else {
        Issue.record("Missing createdAt")
        return
    }

    #expect(createdAtSchema["type"] == .string("string"))
    #expect(createdAtSchema["format"] == .string("date-time"))
}

@Test("Optional enum fields")
func optionalEnum() async throws {
    enum Category: String, Codable, Sendable, CaseIterable {
        case technology
        case science
        case art
    }

    struct Article: Codable, Sendable {
        let title: String
        let category: Category?
    }

    let schema = JSONSchemaGenerator.generate(for: Article.self)

    guard case let .object(root) = schema,
          case let .array(required) = root["required"] else {
        Issue.record("Missing required list")
        return
    }

    let requiredNames = required.compactMap { value -> String? in
        guard case let .string(name) = value else { return nil }
        return name
    }

    #expect(requiredNames.contains("title"))
    #expect(!requiredNames.contains("category")) // optional
}

@Test("Array of enums")
func arrayOfEnums() async throws {
    enum Tag: String, Codable, Sendable, CaseIterable {
        case swift
        case ios
        case macos
    }

    struct Post: Codable, Sendable {
        let tags: [Tag]
    }

    let schema = JSONSchemaGenerator.generate(for: Post.self)

    guard case let .object(root) = schema,
          case let .object(properties) = root["properties"],
          case let .object(tagsSchema) = properties["tags"],
          case let .object(tagItem) = tagsSchema["items"] else {
        Issue.record("Unexpected schema structure")
        return
    }

    #expect(tagsSchema["type"] == .string("array"))
    #expect(tagItem["type"] == .string("string"))

    // Check enum values in array items
    guard case let .array(enumValues) = tagItem["enum"] else {
        Issue.record("Missing enum values in array items")
        return
    }

    let tagValues = enumValues.compactMap { value -> String? in
        guard case let .string(s) = value else { return nil }
        return s
    }

    #expect(tagValues.contains("swift"))
    #expect(tagValues.contains("ios"))
    #expect(tagValues.contains("macos"))
}

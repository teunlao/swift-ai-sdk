import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("ValidateTypes")
struct ValidateTypesTests {
    struct Person: Equatable, Sendable {
        let name: String
        let age: Int
    }

    private static func personSchema() -> FlexibleSchema<Person> {
        let definition = StandardSchemaV1<Person>.Definition(
            vendor: "custom",
            jsonSchema: {
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": "string"]),
                        "age": .object(["type": "number"])
                    ]),
                    "required": .array([.string("name"), .string("age")])
                ])
            },
            validate: { value in
                guard
                    let dict = value as? [String: Any],
                    let name = dict["name"] as? String,
                    let age = dict["age"] as? Int
                else {
                    return .issues("Invalid input")
                }
                return .value(Person(name: name, age: age))
            }
        )

        return FlexibleSchema(StandardSchemaV1(definition: definition))
    }

    @Test("validateTypes returns validated object for valid input")
    func validateTypesReturnsValue() async throws {
        let schema = Self.personSchema()
        let input: [String: Any] = ["name": "John", "age": 30]

        let result = try await validateTypes(
            ValidateTypesOptions(value: input, schema: schema)
        )

        #expect(result == Person(name: "John", age: 30))
    }

    @Test("validateTypes throws TypeValidationError for invalid input")
    func validateTypesThrows() async throws {
        let schema = Self.personSchema()
        let input: [String: Any] = ["name": "John", "age": "30"]

        await #expect(throws: TypeValidationError.self) {
            _ = try await validateTypes(
                ValidateTypesOptions(value: input, schema: schema)
            )
        }
    }

    @Test("safeValidateTypes returns success for valid input")
    func safeValidateTypesSuccess() async throws {
        let schema = Self.personSchema()
        let input: [String: Any] = ["name": "Alice", "age": 25]

        let result = await safeValidateTypes(
            ValidateTypesOptions(value: input, schema: schema)
        )

        switch result {
        case .success(let person, let rawValue):
            #expect(person == Person(name: "Alice", age: 25))
            let rawDict = rawValue as? [String: Any]
            #expect(rawDict?["name"] as? String == "Alice")
            #expect(rawDict?["age"] as? Int == 25)
        case .failure(let error, _):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test("safeValidateTypes returns error for invalid input")
    func safeValidateTypesFailure() async throws {
        let schema = Self.personSchema()
        let input: [String: Any] = ["name": "Alice", "age": "twenty"]

        let result = await safeValidateTypes(
            ValidateTypesOptions(value: input, schema: schema)
        )

        guard case .failure(let error, let rawValue) = result else {
            Issue.record("Expected failure result")
            return
        }

        #expect(error.name == "AI_TypeValidationError")
        let rawDict = rawValue as? [String: Any]
        #expect(rawDict?["age"] as? String == "twenty")
    }
}

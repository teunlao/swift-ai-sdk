import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("Schema Utilities")
struct SchemaTests {
    struct User: Codable, Equatable, Sendable {
        var name: String
    }

    @Test("jsonSchema returns stored JSON representation")
    func jsonSchemaReturnsStoredValue() async throws {
        let expected: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string")
                ])
            ])
        ])

        let schema: Schema<[String: Any]> = jsonSchema(expected, validate: nil)
        let resolved = try await schema.jsonSchema()

        #expect(resolved == expected)
    }

    @Test("jsonSchema without validator passes through values")
    func jsonSchemaPassthroughValidation() async throws {
        let schema: Schema<[String: Any]> = jsonSchema(.object([:]), validate: nil)
        let value: [String: Any] = ["foo": "bar"]
        let result = await schema.validate(value)

        guard case .success(let validated) = result else {
            Issue.record("Expected success but received \(String(describing: result.error))")
            return
        }

        #expect(validated["foo"] as? String == "bar")
    }

    @Test("jsonSchema validates required properties")
    func jsonSchemaValidatesRequiredProperties() async throws {
        let schemaDefinition: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "param1": .object(["type": .string("string")]),
                "param2": .object(["type": .string("number")])
            ]),
            "required": .array([.string("param1"), .string("param2")])
        ])

        let validator = JSONSchemaValidator(schema: schemaDefinition)
        let issues = validator.validate(value: .object(["param1": .string("test")]))
        #expect(!issues.isEmpty)

        let schema: Schema<JSONValue> = jsonSchema(schemaDefinition)

        let directValidation = await schema.validate(["param1": "test"])
        guard case .failure = directValidation else {
            Issue.record("Expected failure for schema.validate")
            return
        }

        let result = await schema.validate(["param1": "test"])

        guard case .failure(let error) = result else {
            Issue.record("Expected validation failure for missing required property")
            return
        }

        #expect(TypeValidationError.isInstance(error))
    }

    @Test("safeParseJSON fails when required missing")
    func safeParseJSONFailsWhenRequiredMissing() async throws {
        let schema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "param1": .object(["type": .string("string")]),
                    "param2": .object(["type": .string("number")])
                ]),
                "required": .array([.string("param1"), .string("param2")])
            ])
        ))

        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(
                text: #"{"param1": "test"}"#,
                schema: schema
            )
        )

        guard case .failure(let error, _) = result else {
            Issue.record("Expected failure but received success")
            return
        }

        #expect(TypeValidationError.isInstance(error))
    }

    @Test("Schema.codable decodes valid payloads")
    func codableSchemaValidates() async throws {
        let schema = Schema<User>.codable(
            User.self,
            jsonSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": "string"])
                ]),
                "required": .array([.string("name")])
            ])
        )

        let result = await schema.validate(["name": "Alice"])

        switch result {
        case .success(let user):
            #expect(user == User(name: "Alice"))
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test("Schema.codable reports type validation errors")
    func codableSchemaReportsErrors() async throws {
        let schema = Schema<User>.codable(
            User.self,
            jsonSchema: .object([
                "type": .string("object"),
                "properties": .object([
                    "name": .object(["type": "string"])
                ]),
                "required": .array([.string("name")])
            ])
        )

        let result = await schema.validate(["name": 42])

        guard case .failure(let error) = result else {
            Issue.record("Expected failure but received success")
            return
        }

        #expect(error.name == "AI_TypeValidationError")
        #expect(error.value as? [String: Any] != nil)
    }

    @Test("lazySchema caches resolved schema")
    func lazySchemaCachesLoader() async throws {
        final class Counter: @unchecked Sendable {
            var value = 0
        }

        let counter = Counter()

        let lazy = lazySchema { () -> Schema<[String: Any]> in
            counter.value += 1
            return jsonSchema(.object([:]), validate: nil)
        }

        _ = try await lazy().jsonSchema()
        _ = try await lazy().jsonSchema()

        #expect(counter.value == 1)
    }

    @Test("standardSchema validates using custom vendor")
    func standardSchemaValidates() async throws {
        struct Result: Equatable, Sendable {
            let name: String
        }

        let definition = StandardSchemaV1<Result>.Definition(
            vendor: "custom",
            jsonSchema: {
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "name": .object(["type": "string"])
                    ])
                ])
            },
            validate: { value in
                if
                    let dictionary = value as? [String: Any],
                    let name = dictionary["name"] as? String
                {
                    return .value(Result(name: name))
                }

                return .issues("Invalid input")
            }
        )

        let schema = standardSchema(StandardSchemaV1(definition: definition))
        let result = await schema.validate(["name": "Bob"])

        switch result {
        case .success(let output):
            #expect(output == Result(name: "Bob"))
        case .failure(let error):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test("standardSchema propagates validation issues")
    func standardSchemaReportsIssues() async throws {
        struct Result: Equatable, Sendable {
            let value: Int
        }

        let definition = StandardSchemaV1<Result>.Definition(
            vendor: "custom",
            validate: { _ in
                .issues("boom")
            }
        )

        let schema = standardSchema(StandardSchemaV1(definition: definition))
        let outcome = await schema.validate(["value": 42])

        guard case .failure(let error) = outcome else {
            Issue.record("Expected failure but received success")
            return
        }

        #expect(error.name == "AI_TypeValidationError")
        #expect(error.value as? [String: Any] != nil)
        let causeDescription: String
        if let cause = error.cause {
            causeDescription = String(describing: cause)
        } else {
            causeDescription = "nil"
        }
        #expect(causeDescription.contains("Schema validation issues"))
    }

    @Test("standardSchema rejects zod vendor")
    func standardSchemaRejectsZod() async throws {
        let definition = StandardSchemaV1<String>.Definition(
            vendor: "zod",
            validate: { _ in .issues("unreachable") }
        )

        let schema = standardSchema(StandardSchemaV1(definition: definition))

        await #expect(throws: UnsupportedStandardSchemaVendorError.self) {
            _ = try await schema.jsonSchema()
        }

        let result = await schema.validate("value")
        guard case .failure(let error) = result else {
            Issue.record("Expected failure for zod schema")
            return
        }

        #expect(error.name == "AI_TypeValidationError")
    }

    @Test("asSchema returns default schema when nil")
    func asSchemaReturnsDefault() async throws {
        let schema: Schema<[String: Any]> = asSchema(nil)
        let resolved = try await schema.jsonSchema()

        #expect(resolved == .object([
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ]))
    }

    @Test("standardSchema uses fallback JSON schema when resolver missing")
    func standardSchemaFallbackJsonSchema() async throws {
        let definition = StandardSchemaV1<[String: Any]>.Definition(
            vendor: "custom",
            validate: { value in
                guard let dict = value as? [String: Any] else {
                    return .issues("not a dictionary")
                }
                return .value(dict)
            }
        )

        let schema = standardSchema(StandardSchemaV1(definition: definition))
        let resolved = try await schema.jsonSchema()

        #expect(resolved == .object([
            "properties": .object([:]),
            "additionalProperties": .bool(false)
        ]))
    }

    @Test("standardSchema passes through provided JSON schema for other vendors")
    func standardSchemaVendorSpecificJsonSchema() async throws {
        let expected: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                "value": .object(["type": "number"])
            ])
        ])

        let definition = StandardSchemaV1<Double>.Definition(
            vendor: "arktype",
            jsonSchema: { expected },
            validate: { value in
                guard let number = value as? Double else {
                    return .issues("expected number")
                }
                return .value(number)
            }
        )

        let schema = standardSchema(StandardSchemaV1(definition: definition))
        let resolved = try await schema.jsonSchema()
        #expect(resolved == expected)

        let result = await schema.validate(42.0)
        guard case .success(let typed) = result else {
            Issue.record("Expected success for arktype vendor schema")
            return
        }
        #expect(typed == 42.0)
    }
}

import Testing
@testable import SwiftAISDK

@Suite("ParseJSON")
struct ParseJSONTests {
    struct UserPayload: Decodable, Equatable, Sendable {
        struct User: Decodable, Equatable, Sendable {
            let id: Int
            let name: String

            init(id: Int, name: String) {
                self.id = id
                self.name = name
            }

            enum CodingKeys: String, CodingKey {
                case id
                case name
            }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let idString = try container.decode(String.self, forKey: .id)
                guard let id = Int(idString) else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .id,
                        in: container,
                        debugDescription: "Expected numeric string for id"
                    )
                }
                self.id = id
                self.name = try container.decode(String.self, forKey: .name)
            }
        }

        let user: User
    }

    struct UppercaseArray: Decodable, Equatable, Sendable {
        let items: [String]

        init(items: [String]) {
            self.items = items
        }

        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            var values: [String] = []
            while !container.isAtEnd {
                let value = try container.decode(String.self).uppercased()
                values.append(value)
            }
            self.items = values
        }
    }

    private func userSchema() -> FlexibleSchema<UserPayload> {
        let schema = Schema<UserPayload>.codable(
            UserPayload.self,
            jsonSchema: .object([
                "type": "object",
                "properties": [
                    "user": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "string"],
                            "name": ["type": "string"]
                        ],
                        "required": ["id", "name"]
                    ]
                ],
                "required": ["user"]
            ])
        )

        return FlexibleSchema(schema)
    }

    private func uppercaseArraySchema() -> FlexibleSchema<UppercaseArray> {
        let schema = Schema<UppercaseArray>.codable(
            UppercaseArray.self,
            jsonSchema: .object([
                "type": "array",
                "items": ["type": "string"]
            ])
        )

        return FlexibleSchema(schema)
    }

    @Test("parseJSON parses JSON without schema")
    func parseJSONWithoutSchema() async throws {
        let result = try await parseJSON(
            ParseJSONOptions(text: #"{"foo":"bar"}"#)
        )

        let expected: JSONValue = ["foo": "bar"]
        #expect(result == expected)
    }

    @Test("parseJSON parses JSON with schema validation")
    func parseJSONWithSchema() async throws {
        let schema = userSchema()
        let result = try await parseJSON(
            ParseJSONWithSchemaOptions(
                text: #"{"user": {"id": "42", "name": "Alice"}}"#,
                schema: schema
            )
        )

        #expect(result == UserPayload(user: .init(id: 42, name: "Alice")))
    }

    @Test("parseJSON throws JSONParseError on invalid JSON")
    func parseJSONThrowsOnInvalid() async {
        await #expect(throws: JSONParseError.self) {
            _ = try await parseJSON(ParseJSONOptions(text: "invalid"))
        }
    }

    @Test("parseJSON throws TypeValidationError when schema validation fails")
    func parseJSONThrowsOnSchemaFailure() async {
        let schema = userSchema()

        await #expect(throws: TypeValidationError.self) {
            _ = try await parseJSON(
                ParseJSONWithSchemaOptions(
                    text: #"{"user": {"id": "x", "name": "Alice"}}"#,
                    schema: schema
                )
            )
        }
    }

    @Test("safeParseJSON returns success for valid JSON without schema")
    func safeParseJSONWithoutSchema() async {
        let result = await safeParseJSON(
            ParseJSONOptions(text: #"{"foo": "bar"}"#)
        )

        switch result {
        case .success(let value, let rawValue):
            let expected: JSONValue = ["foo": "bar"]
            #expect(value == expected)
            let rawDict = rawValue as? [String: Any]
            #expect(rawDict?["foo"] as? String == "bar")
        case .failure(let error, _):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test("safeParseJSON preserves rawValue after schema transformation")
    func safeParseJSONWithSchema() async {
        let schema = userSchema()

        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(
                text: #"{"user": {"id": "123", "name": "John"}}"#,
                schema: schema
            )
        )

        switch result {
        case .success(let value, let rawValue):
            #expect(value == UserPayload(user: .init(id: 123, name: "John")))
            let rawDict = rawValue as? [String: Any]
            let user = rawDict?["user"] as? [String: Any]
            #expect(user?["id"] as? String == "123")
        case .failure(let error, _):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test("safeParseJSON returns failure for invalid JSON")
    func safeParseJSONInvalid() async {
        let result = await safeParseJSON(ParseJSONOptions(text: "invalid"))

        guard case .failure(let error, let raw) = result else {
            Issue.record("Expected failure")
            return
        }

        #expect(error is JSONParseError)
        #expect(raw == nil)
    }

    @Test("safeParseJSON returns failure when schema validation fails")
    func safeParseJSONSchemaFailure() async {
        let schema = userSchema()
        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(
                text: #"{"user": {"id": "abc", "name": "Alice"}}"#,
                schema: schema
            )
        )

        guard case .failure(let error, let raw) = result else {
            Issue.record("Expected failure result")
            return
        }

        #expect(error is TypeValidationError)
        let user = (raw as? [String: Any])?["user"] as? [String: Any]
        #expect(user?["id"] as? String == "abc")
    }

    @Test("safeParseJSON handles arrays with schema transformations")
    func safeParseJSONArrayTransform() async {
        let schema = uppercaseArraySchema()
        let result = await safeParseJSON(
            ParseJSONWithSchemaOptions(
                text: #"["hello", "world"]"#,
                schema: schema
            )
        )

        switch result {
        case .success(let value, let rawValue):
            #expect(value == UppercaseArray(items: ["HELLO", "WORLD"]))
            let rawArray = rawValue as? [String]
            #expect(rawArray == ["hello", "world"])
        case .failure(let error, _):
            Issue.record("Unexpected failure: \(error)")
        }
    }

    @Test("isParsableJson returns true for valid JSON and false otherwise")
    func isParsableJsonChecks() {
        #expect(isParsableJson(#"{"foo": "bar"}"#) == true)
        #expect(isParsableJson("[1, 2, 3]") == true)
        #expect(isParsableJson("invalid") == false)
        #expect(isParsableJson(#"{"foo": }"#) == false)
    }
}

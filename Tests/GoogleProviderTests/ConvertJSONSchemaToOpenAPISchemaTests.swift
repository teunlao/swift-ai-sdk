import Foundation
import Testing
@testable import GoogleProvider
@testable import AISDKProvider

@Suite("convertJSONSchemaToOpenAPISchema")
struct ConvertJSONSchemaToOpenAPISchemaTests {
    private func canonicalJSON(_ value: Any) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    @Test("should remove additionalProperties and $schema")
    func removeAdditionalPropertiesAndSchema() throws {
        let input: JSONValue = .object([
            "$schema": .string("http://json-schema.org/draft-07/schema#"),
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")]),
                "age": .object(["type": .string("number")])
            ]),
            "additionalProperties": .bool(false)
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"] as [String: Any],
                "age": ["type": "number"] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        #expect(result["$schema"] == nil)
        #expect(result["additionalProperties"] == nil)

        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should remove additionalProperties object from nested object schemas")
    func removeAdditionalPropertiesFromNested() throws {
        let input: JSONValue = .object([
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

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "keys": [
                    "type": "object",
                    "description": "Description for the key"
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle nested objects and arrays")
    func handleNestedObjectsAndArrays() throws {
        let input: JSONValue = .object([
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

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "users": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "id": ["type": "number"] as [String: Any],
                            "name": ["type": "string"] as [String: Any]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        #expect(result["additionalProperties"] == nil)
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should convert \"const\" to \"enum\" with a single value")
    func convertConstToEnum() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "status": .object(["const": .string("active")])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "status": ["enum": ["active"]] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle allOf, anyOf, and oneOf")
    func handleCombinators() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "allOfProp": .object(["allOf": .array([
                    .object(["type": .string("string")]),
                    .object(["minLength": .number(5)])
                ])]),
                "anyOfProp": .object(["anyOf": .array([
                    .object(["type": .string("string")]),
                    .object(["type": .string("number")])
                ])]),
                "oneOfProp": .object(["oneOf": .array([
                    .object(["type": .string("boolean")]),
                    .object(["type": .string("null")])
                ])])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "allOfProp": [
                    "allOf": [
                        ["type": "string"],
                        ["minLength": 5.0]
                    ]
                ] as [String: Any],
                "anyOfProp": [
                    "anyOf": [
                        ["type": "string"],
                        ["type": "number"]
                    ]
                ] as [String: Any],
                "oneOfProp": [
                    "oneOf": [
                        ["type": "boolean"],
                        ["type": "null"]
                    ]
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should convert \"format: date-time\" to \"format: date-time\"")
    func convertDateTimeFormat() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "timestamp": .object([
                    "type": .string("string"),
                    "format": .string("date-time")
                ])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "timestamp": [
                    "type": "string",
                    "format": "date-time"
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle required properties")
    func handleRequiredProperties() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "id": .object(["type": .string("number")]),
                "name": .object(["type": .string("string")])
            ]),
            "required": .array([.string("id")])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "id": ["type": "number"] as [String: Any],
                "name": ["type": "string"] as [String: Any]
            ] as [String: Any],
            "required": ["id"]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should convert deeply nested \"const\" to \"enum\"")
    func deeplyNestedConst() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "nested": .object([
                    "type": .string("object"),
                    "properties": .object([
                        "deeplyNested": .object([
                            "anyOf": .array([
                                .object([
                                    "type": .string("object"),
                                    "properties": .object([
                                        "value": .object([
                                            "const": .string("specific value")
                                        ])
                                    ])
                                ]),
                                .object([
                                    "type": .string("string")
                                ])
                            ])
                        ])
                    ])
                ])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "nested": [
                    "type": "object",
                    "properties": [
                        "deeplyNested": [
                            "anyOf": [
                                [
                                    "type": "object",
                                    "properties": [
                                        "value": ["enum": ["specific value"]] as [String: Any]
                                    ] as [String: Any]
                                ],
                                [
                                    "type": "string"
                                ]
                            ]
                        ] as [String: Any]
                    ] as [String: Any]
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should correctly convert a complex schema with nested const and anyOf")
    func complexSchemaWithNestedConstAndAnyOf() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object([
                    "type": .string("string")
                ]),
                "age": .object([
                    "type": .string("number")
                ]),
                "contact": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "type": .object([
                                    "type": .string("string"),
                                    "const": .string("email")
                                ]),
                                "value": .object([
                                    "type": .string("string")
                                ])
                            ]),
                            "required": .array([.string("type"), .string("value")]),
                            "additionalProperties": .bool(false)
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "type": .object([
                                    "type": .string("string"),
                                    "const": .string("phone")
                                ]),
                                "value": .object([
                                    "type": .string("string")
                                ])
                            ]),
                            "required": .array([.string("type"), .string("value")]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ]),
                "occupation": .object([
                    "anyOf": .array([
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "type": .object([
                                    "type": .string("string"),
                                    "const": .string("employed")
                                ]),
                                "company": .object([
                                    "type": .string("string")
                                ]),
                                "position": .object([
                                    "type": .string("string")
                                ])
                            ]),
                            "required": .array([.string("type"), .string("company"), .string("position")]),
                            "additionalProperties": .bool(false)
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "type": .object([
                                    "type": .string("string"),
                                    "const": .string("student")
                                ]),
                                "school": .object([
                                    "type": .string("string")
                                ]),
                                "grade": .object([
                                    "type": .string("number")
                                ])
                            ]),
                            "required": .array([.string("type"), .string("school"), .string("grade")]),
                            "additionalProperties": .bool(false)
                        ]),
                        .object([
                            "type": .string("object"),
                            "properties": .object([
                                "type": .object([
                                    "type": .string("string"),
                                    "const": .string("unemployed")
                                ])
                            ]),
                            "required": .array([.string("type")]),
                            "additionalProperties": .bool(false)
                        ])
                    ])
                ])
            ]),
            "required": .array([.string("name"), .string("age"), .string("contact"), .string("occupation")]),
            "additionalProperties": .bool(false),
            "$schema": .string("http://json-schema.org/draft-07/schema#")
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "name": [
                    "type": "string"
                ] as [String: Any],
                "age": [
                    "type": "number"
                ] as [String: Any],
                "contact": [
                    "anyOf": [
                        [
                            "type": "object",
                            "properties": [
                                "type": [
                                    "type": "string",
                                    "enum": ["email"]
                                ] as [String: Any],
                                "value": [
                                    "type": "string"
                                ] as [String: Any]
                            ] as [String: Any],
                            "required": ["type", "value"]
                        ],
                        [
                            "type": "object",
                            "properties": [
                                "type": [
                                    "type": "string",
                                    "enum": ["phone"]
                                ] as [String: Any],
                                "value": [
                                    "type": "string"
                                ] as [String: Any]
                            ] as [String: Any],
                            "required": ["type", "value"]
                        ]
                    ]
                ] as [String: Any],
                "occupation": [
                    "anyOf": [
                        [
                            "type": "object",
                            "properties": [
                                "type": [
                                    "type": "string",
                                    "enum": ["employed"]
                                ] as [String: Any],
                                "company": [
                                    "type": "string"
                                ] as [String: Any],
                                "position": [
                                    "type": "string"
                                ] as [String: Any]
                            ] as [String: Any],
                            "required": ["type", "company", "position"]
                        ],
                        [
                            "type": "object",
                            "properties": [
                                "type": [
                                    "type": "string",
                                    "enum": ["student"]
                                ] as [String: Any],
                                "school": [
                                    "type": "string"
                                ] as [String: Any],
                                "grade": [
                                    "type": "number"
                                ] as [String: Any]
                            ] as [String: Any],
                            "required": ["type", "school", "grade"]
                        ],
                        [
                            "type": "object",
                            "properties": [
                                "type": [
                                    "type": "string",
                                    "enum": ["unemployed"]
                                ] as [String: Any]
                            ] as [String: Any],
                            "required": ["type"]
                        ]
                    ]
                ] as [String: Any]
            ] as [String: Any],
            "required": ["name", "age", "contact", "occupation"]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        #expect(result["$schema"] == nil)
        #expect(result["additionalProperties"] == nil)

        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle null type correctly")
    func handleNullType() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "nullableField": .object(["type": .array([.string("string"), .string("null")])]),
                "explicitNullField": .object(["type": .string("null")])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "nullableField": [
                    "anyOf": [
                        ["type": "string"]
                    ],
                    "nullable": true
                ] as [String: Any],
                "explicitNullField": [
                    "type": "null"
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle descriptions")
    func handleDescriptions() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "description": .string("A user object"),
            "properties": .object([
                "id": .object([
                    "type": .string("number"),
                    "description": .string("The user ID")
                ]),
                "name": .object([
                    "type": .string("string"),
                    "description": .string("The user's full name")
                ]),
                "email": .object([
                    "type": .string("string"),
                    "format": .string("email"),
                    "description": .string("The user's email address")
                ])
            ]),
            "required": .array([.string("id"), .string("name")])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "description": "A user object",
            "properties": [
                "id": [
                    "type": "number",
                    "description": "The user ID"
                ] as [String: Any],
                "name": [
                    "type": "string",
                    "description": "The user's full name"
                ] as [String: Any],
                "email": [
                    "type": "string",
                    "format": "email",
                    "description": "The user's email address"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["id", "name"]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should return undefined for empty object schemas at root level")
    func rootEmptyObjectSchemas() throws {
        let emptyObjectSchemas: [JSONValue] = [
            .object(["type": .string("object")]),
            .object(["type": .string("object"), "properties": .object([:])])
        ]

        for schema in emptyObjectSchemas {
            #expect(convertJSONSchemaToOpenAPISchema(schema) == nil)
        }
    }

    @Test("should preserve nested empty object schemas to avoid breaking required array validation")
    func preserveNestedEmptyObjectSchemasWithDescriptions() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "url": .object([
                    "type": .string("string"),
                    "description": .string("URL to navigate to")
                ]),
                "launchOptions": .object([
                    "type": .string("object"),
                    "description": .string("PuppeteerJS LaunchOptions")
                ]),
                "allowDangerous": .object([
                    "type": .string("boolean"),
                    "description": .string("Allow dangerous options")
                ])
            ]),
            "required": .array([.string("url"), .string("launchOptions")])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "url": [
                    "type": "string",
                    "description": "URL to navigate to"
                ] as [String: Any],
                "launchOptions": [
                    "type": "object",
                    "description": "PuppeteerJS LaunchOptions"
                ] as [String: Any],
                "allowDangerous": [
                    "type": "boolean",
                    "description": "Allow dangerous options"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["url", "launchOptions"]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should preserve nested empty object schemas without descriptions")
    func preserveNestedEmptyObjectSchemasWithoutDescriptions() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "options": .object([
                    "type": .string("object")
                ])
            ]),
            "required": .array([.string("options")])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "options": [
                    "type": "object"
                ] as [String: Any]
            ] as [String: Any],
            "required": ["options"]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle non-empty object schemas")
    func handleNonEmptyObjectSchemas() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "name": .object(["type": .string("string")])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "name": ["type": "string"] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should convert string enum properties")
    func convertStringEnum() throws {
        let input: JSONValue = .object([
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

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "kind": [
                    "type": "string",
                    "enum": ["text", "code", "image"]
                ] as [String: Any]
            ] as [String: Any],
            "required": ["kind"]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        #expect(result["additionalProperties"] == nil)
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should convert nullable string enum")
    func convertNullableStringEnum() throws {
        let input: JSONValue = .object([
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

        let expected: [String: Any] = [
            "required": ["fieldD"],
            "type": "object",
            "properties": [
                "fieldD": [
                    "nullable": true,
                    "type": "string",
                    "enum": ["a", "b", "c"]
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should handle type arrays with multiple non-null types plus null")
    func handleTypeArraysWithMultipleNonNullTypesPlusNull() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "multiTypeField": .object([
                    "type": .array([.string("string"), .string("number"), .string("null")])
                ])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "multiTypeField": [
                    "anyOf": [
                        ["type": "string"],
                        ["type": "number"]
                    ],
                    "nullable": true
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }

    @Test("should convert type arrays without null to anyOf")
    func convertTypeArraysWithoutNullToAnyOf() throws {
        let input: JSONValue = .object([
            "type": .string("object"),
            "properties": .object([
                "multiTypeField": .object([
                    "type": .array([.string("string"), .string("number")])
                ])
            ])
        ])

        let expected: [String: Any] = [
            "type": "object",
            "properties": [
                "multiTypeField": [
                    "anyOf": [
                        ["type": "string"],
                        ["type": "number"]
                    ]
                ] as [String: Any]
            ] as [String: Any]
        ]

        let result = try #require(convertJSONSchemaToOpenAPISchema(input) as? [String: Any])
        let actualJSON = try canonicalJSON(result)
        let expectedJSON = try canonicalJSON(expected)
        #expect(actualJSON == expectedJSON)
    }
}

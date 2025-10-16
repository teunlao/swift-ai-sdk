import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("validateUIMessages")
struct ValidateUIMessagesTests {
    // MARK: - Parameter validation

    @Test("throws when messages parameter is nil")
    func throwsWhenMessagesNil() async {
        do {
            _ = try await validateUIMessages(messages: nil as Any?)
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(InvalidArgumentError.isInstance(error))
        }
    }

    @Test("throws when messages parameter is NSNull")
    func throwsWhenMessagesNull() async {
        do {
            _ = try await validateUIMessages(messages: NSNull())
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(InvalidArgumentError.isInstance(error))
        }
    }

    // MARK: - Metadata

    @Test("validates metadata without schema")
    func validatesMetadataWithoutSchema() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "user",
                "metadata": ["foo": "bar"],
                "parts": [
                    ["type": "text", "text": "Hello, world!"]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .user,
                metadata: .object(["foo": .string("bar")]),
                parts: [.text(TextUIPart(text: "Hello, world!", state: .streaming))]
            )
        ])
    }

    @Test("validates metadata with schema")
    func validatesMetadataWithSchema() async throws {
        let metadataSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "foo": .object(["type": .string("string")])
                ]),
                "required": .array([.string("foo")]),
                "additionalProperties": .bool(false)
            ])
        ))

        let messages = try await validateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "user",
                    "metadata": ["foo": "bar"],
                    "parts": [
                        ["type": "text", "text": "Hello, world!"]
                    ]
                ]
            ],
            metadataSchema: metadataSchema
        )

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .user,
                metadata: .object(["foo": .string("bar")]),
                parts: [.text(TextUIPart(text: "Hello, world!", state: .streaming))]
            )
        ])
    }

    @Test("throws when metadata fails validation")
    func throwsWhenMetadataInvalid() async {
        let metadataSchema = FlexibleSchema(jsonSchema(
            .object([
                "type": .string("object"),
                "properties": .object([
                    "foo": .object(["type": .string("string")])
                ]),
                "required": .array([.string("foo")]),
                "additionalProperties": .bool(false)
            ])
        ))

        do {
            _ = try await validateUIMessages(
                messages: [
                    [
                        "id": "1",
                        "role": "user",
                        "metadata": ["foo": 123],
                        "parts": [
                            ["type": "text", "text": "Hello, world!"]
                        ]
                    ]
                ],
                metadataSchema: metadataSchema
            )
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(TypeValidationError.isInstance(error))
        }
    }

    @Test("validates text provider metadata")
    func validatesTextProviderMetadata() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "user",
                "parts": [
                    [
                        "type": "text",
                        "text": "Hello, world!",
                        "providerMetadata": [
                            "someProvider": [
                                "custom": "metadata"
                            ]
                        ]
                    ]
                ]
            ]
        ])

        let expectedMetadata: ProviderMetadata = [
            "someProvider": [
                "custom": .string("metadata")
            ]
        ]

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .user,
                metadata: nil,
                parts: [
                    .text(
                        TextUIPart(
                            text: "Hello, world!",
                            state: .streaming,
                            providerMetadata: expectedMetadata
                        )
                    )
                ]
            )
        ])
    }

    // MARK: - Simple parts

    @Test("validates user text message")
    func validatesTextPart() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "user",
                "parts": [
                    ["type": "text", "text": "Hello, world!"]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .user,
                metadata: nil,
                parts: [.text(TextUIPart(text: "Hello, world!", state: .streaming))]
            )
        ])
    }

    @Test("validates reasoning part")
    func validatesReasoningPart() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    ["type": "reasoning", "text": "Thinking..."]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [.reasoning(ReasoningUIPart(text: "Thinking...", state: .streaming))]
            )
        ])
    }

    @Test("validates source url part")
    func validatesSourceUrlPart() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "source-url",
                        "sourceId": "1",
                        "url": "https://example.com",
                        "title": "Example"
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .sourceURL(
                        SourceUrlUIPart(
                            sourceId: "1",
                            url: "https://example.com",
                            title: "Example",
                            providerMetadata: nil
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates source document part")
    func validatesSourceDocumentPart() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "source-document",
                        "sourceId": "1",
                        "mediaType": "text/plain",
                        "title": "Example",
                        "filename": "example.txt"
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .sourceDocument(
                        SourceDocumentUIPart(
                            sourceId: "1",
                            mediaType: "text/plain",
                            title: "Example",
                            filename: "example.txt",
                            providerMetadata: nil
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates file part")
    func validatesFilePart() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "file",
                        "mediaType": "text/plain",
                        "url": "https://example.com"
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .file(
                        FileUIPart(
                            mediaType: "text/plain",
                            filename: nil,
                            url: "https://example.com",
                            providerMetadata: nil
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates step-start part")
    func validatesStepStartPart() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    ["type": "step-start"]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [.stepStart]
            )
        ])
    }

    // MARK: - Data parts

    @Test("validates multiple data parts")
    func validatesDataParts() async throws {
        let dataSchemas: [String: FlexibleSchema<JSONValue>] = [
            "foo": FlexibleSchema(jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "foo": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("foo")]),
                    "additionalProperties": .bool(false)
                ])
            )),
            "bar": FlexibleSchema(jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "bar": .object(["type": .string("number")])
                    ]),
                    "required": .array([.string("bar")]),
                    "additionalProperties": .bool(false)
                ])
            ))
        ]

        let messages = try await validateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "assistant",
                    "parts": [
                        ["type": "data-foo", "data": ["foo": "bar"]],
                        ["type": "data-bar", "data": ["bar": 123]]
                    ]
                ]
            ],
            dataSchemas: dataSchemas
        )

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .data(DataUIPart(typeIdentifier: "data-foo", id: nil, data: .object(["foo": .string("bar")]))),
                    .data(DataUIPart(typeIdentifier: "data-bar", id: nil, data: .object(["bar": .number(123)])))
                ]
            )
        ])
    }

    @Test("throws when data part fails validation")
    func throwsWhenDataInvalid() async {
        let dataSchemas: [String: FlexibleSchema<JSONValue>] = [
            "foo": FlexibleSchema(jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "foo": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("foo")]),
                    "additionalProperties": .bool(false)
                ])
            ))
        ]

        do {
            _ = try await validateUIMessages(
                messages: [
                    [
                        "id": "1",
                        "role": "assistant",
                        "parts": [
                            ["type": "data-foo", "data": ["foo": 123]]
                        ]
                    ]
                ],
                dataSchemas: dataSchemas
            )
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(TypeValidationError.isInstance(error))
        }
    }

    @Test("throws when data schema missing")
    func throwsWhenDataSchemaMissing() async {
        do {
            _ = try await validateUIMessages(
                messages: [
                    [
                        "id": "1",
                        "role": "assistant",
                        "parts": [
                            ["type": "data-bar", "data": ["foo": "bar"]]
                        ]
                    ]
                ],
                dataSchemas: [
                    "foo": FlexibleSchema(jsonSchema(.object(["type": .string("object")])) )
                ]
            )
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(TypeValidationError.isInstance(error))
        }
    }

    // MARK: - Dynamic tool parts

    @Test("validates dynamic tool part input-streaming")
    func validatesDynamicToolInputStreaming() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "dynamic-tool",
                        "toolName": "foo",
                        "toolCallId": "1",
                        "state": "input-streaming",
                        "input": ["foo": "bar"]
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .dynamicTool(
                        UIDynamicToolUIPart(
                            toolName: "foo",
                            toolCallId: "1",
                            state: .inputStreaming,
                            input: .object(["foo": .string("bar")]),
                            output: nil,
                            errorText: nil,
                            callProviderMetadata: nil,
                            preliminary: nil
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates dynamic tool part input-available")
    func validatesDynamicToolInputAvailable() async throws {
        let metadata: ProviderMetadata = [
            "provider": ["meta": .string("value")]
        ]

        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "dynamic-tool",
                        "toolName": "foo",
                        "toolCallId": "1",
                        "state": "input-available",
                        "input": ["foo": "bar"],
                        "callProviderMetadata": [
                            "provider": ["meta": "value"]
                        ]
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .dynamicTool(
                        UIDynamicToolUIPart(
                            toolName: "foo",
                            toolCallId: "1",
                            state: .inputAvailable,
                            input: .object(["foo": .string("bar")]),
                            output: nil,
                            errorText: nil,
                            callProviderMetadata: metadata,
                            preliminary: nil
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates dynamic tool part output-available")
    func validatesDynamicToolOutputAvailable() async throws {
        let metadata: ProviderMetadata = [
            "provider": ["meta": .string("value")]
        ]

        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "dynamic-tool",
                        "toolName": "foo",
                        "toolCallId": "1",
                        "state": "output-available",
                        "input": ["foo": "bar"],
                        "output": ["result": "ok"],
                        "callProviderMetadata": [
                            "provider": ["meta": "value"]
                        ],
                        "preliminary": true
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .dynamicTool(
                        UIDynamicToolUIPart(
                            toolName: "foo",
                            toolCallId: "1",
                            state: .outputAvailable,
                            input: .object(["foo": .string("bar")]),
                            output: .object(["result": .string("ok")]),
                            errorText: nil,
                            callProviderMetadata: metadata,
                            preliminary: true
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates dynamic tool part output-error")
    func validatesDynamicToolOutputError() async throws {
        let metadata: ProviderMetadata = [
            "provider": ["meta": .string("value")]
        ]

        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "dynamic-tool",
                        "toolName": "foo",
                        "toolCallId": "1",
                        "state": "output-error",
                        "input": ["foo": "bar"],
                        "errorText": "Failure",
                        "callProviderMetadata": [
                            "provider": ["meta": "value"]
                        ]
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .dynamicTool(
                        UIDynamicToolUIPart(
                            toolName: "foo",
                            toolCallId: "1",
                            state: .outputError,
                            input: .object(["foo": .string("bar")]),
                            output: nil,
                            errorText: "Failure",
                            callProviderMetadata: metadata,
                            preliminary: nil
                        )
                    )
                ]
            )
        ])
    }

    // MARK: - Tool parts (structure)

    @Test("validates tool part input-streaming")
    func validatesToolInputStreaming() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "tool-foo",
                        "toolCallId": "1",
                        "state": "input-streaming",
                        "input": ["foo": "bar"],
                        "providerExecuted": true
                    ]
                ]
            ]
        ])

        #expect(messages == [
            UIMessage(
                id: "1",
                role: .assistant,
                metadata: nil,
                parts: [
                    .tool(
                        UIToolUIPart(
                            toolName: "foo",
                            toolCallId: "1",
                            state: .inputStreaming,
                            input: .object(["foo": .string("bar")]),
                            output: nil,
                            rawInput: nil,
                            errorText: nil,
                            providerExecuted: true,
                            callProviderMetadata: nil,
                            preliminary: nil,
                            approval: nil
                        )
                    )
                ]
            )
        ])
    }

    @Test("validates tool part input-available")
    func validatesToolInputAvailable() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "tool-foo",
                        "toolCallId": "1",
                        "state": "input-available",
                        "input": ["foo": "bar"],
                        "providerExecuted": true
                    ]
                ]
            ]
        ])

        guard let part = messages.first?.parts.first else {
            Issue.record("Expected tool part")
            return
        }

        #expect(part == .tool(
            UIToolUIPart(
                toolName: "foo",
                toolCallId: "1",
                state: .inputAvailable,
                input: .object(["foo": .string("bar")]),
                output: nil,
                rawInput: nil,
                errorText: nil,
                providerExecuted: true,
                callProviderMetadata: nil,
                preliminary: nil,
                approval: nil
            )
        ))
    }

    @Test("validates tool part output-available")
    func validatesToolOutputAvailable() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "tool-foo",
                        "toolCallId": "1",
                        "state": "output-available",
                        "input": ["foo": "bar"],
                        "output": ["result": "success"],
                        "providerExecuted": true
                    ]
                ]
            ]
        ])

        guard let part = messages.first?.parts.first else {
            Issue.record("Expected tool part")
            return
        }

        #expect(part == .tool(
            UIToolUIPart(
                toolName: "foo",
                toolCallId: "1",
                state: .outputAvailable,
                input: .object(["foo": .string("bar")]),
                output: .object(["result": .string("success")]),
                rawInput: nil,
                errorText: nil,
                providerExecuted: true,
                callProviderMetadata: nil,
                preliminary: nil,
                approval: nil
            )
        ))
    }

    @Test("validates tool part output-error")
    func validatesToolOutputError() async throws {
        let messages = try await validateUIMessages(messages: [
            [
                "id": "1",
                "role": "assistant",
                "parts": [
                    [
                        "type": "tool-foo",
                        "toolCallId": "1",
                        "state": "output-error",
                        "input": ["foo": "bar"],
                        "errorText": "Tool execution failed",
                        "providerExecuted": true
                    ]
                ]
            ]
        ])

        guard let part = messages.first?.parts.first else {
            Issue.record("Expected tool part")
            return
        }

        #expect(part == .tool(
            UIToolUIPart(
                toolName: "foo",
                toolCallId: "1",
                state: .outputError,
                input: .object(["foo": .string("bar")]),
                output: nil,
                rawInput: nil,
                errorText: "Tool execution failed",
                providerExecuted: true,
                callProviderMetadata: nil,
                preliminary: nil,
                approval: nil
            )
        ))
    }

    // MARK: - Tool schema validation

    @Test("validates tool input with schema")
    func validatesToolInputWithSchema() async throws {
        let tool = Tool(
            inputSchema: stringFooSchema(),
            outputSchema: nil
        )

        let messages = try await validateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "assistant",
                    "parts": [
                        [
                            "type": "tool-foo",
                            "toolCallId": "1",
                            "state": "input-available",
                            "input": ["foo": "bar"],
                            "providerExecuted": true
                        ]
                    ]
                ]
            ],
            tools: ["foo": tool]
        )

        #expect(messages.count == 1)
    }

    @Test("validates tool output with schema")
    func validatesToolOutputWithSchema() async throws {
        let tool = Tool(
            inputSchema: stringFooSchema(),
            outputSchema: FlexibleSchema(jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "result": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("result")]),
                    "additionalProperties": .bool(false)
                ])
            ))
        )

        let messages = try await validateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "assistant",
                    "parts": [
                        [
                            "type": "tool-foo",
                            "toolCallId": "1",
                            "state": "output-available",
                            "input": ["foo": "bar"],
                            "output": ["result": "ok"]
                        ]
                    ]
                ]
            ],
            tools: ["foo": tool]
        )

        #expect(messages.count == 1)
    }

    @Test("throws when tool input invalid")
    func throwsWhenToolInputInvalid() async {
        let tool = Tool(
            inputSchema: stringFooSchema(),
            outputSchema: nil
        )

        do {
            _ = try await validateUIMessages(
                messages: [
                    [
                        "id": "1",
                        "role": "assistant",
                        "parts": [
                            [
                                "type": "tool-foo",
                                "toolCallId": "1",
                                "state": "input-available",
                                "input": ["foo": 123]
                            ]
                        ]
                    ]
                ],
                tools: ["foo": tool]
            )
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(TypeValidationError.isInstance(error))
        }
    }

    @Test("throws when tool output invalid")
    func throwsWhenToolOutputInvalid() async {
        let tool = Tool(
            inputSchema: stringFooSchema(),
            outputSchema: FlexibleSchema(jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "result": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("result")]),
                    "additionalProperties": .bool(false)
                ])
            ))
        )

        do {
            _ = try await validateUIMessages(
                messages: [
                    [
                        "id": "1",
                        "role": "assistant",
                        "parts": [
                            [
                                "type": "tool-foo",
                                "toolCallId": "1",
                                "state": "output-available",
                                "input": ["foo": "bar"],
                                "output": ["result": 123]
                            ]
                        ]
                    ]
                ],
                tools: ["foo": tool]
            )
            Issue.record("Expected validateUIMessages to throw")
        } catch {
            #expect(TypeValidationError.isInstance(error))
        }
    }

    @Test("does not validate input for streaming state")
    func skipsValidationForStreamingInput() async throws {
        let tool = Tool(
            inputSchema: stringFooSchema(),
            outputSchema: nil
        )

        let messages = try await validateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "assistant",
                    "parts": [
                        [
                            "type": "tool-foo",
                            "toolCallId": "1",
                            "state": "input-streaming",
                            "input": ["foo": 123],
                            "providerExecuted": true
                        ]
                    ]
                ]
            ],
            tools: ["foo": tool]
        )

        #expect(messages.count == 1)
    }
}

// MARK: - safeValidateUIMessages tests

@Suite("safeValidateUIMessages")
struct SafeValidateUIMessagesTests {
    @Test("returns success for valid messages")
    func returnsSuccess() async {
        let result = await safeValidateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "user",
                    "parts": [
                        ["type": "text", "text": "Hello, world!"]
                    ]
                ]
            ] as [Any]
        )

        #expect(result.success)
        #expect(result.data == [
            UIMessage(
                id: "1",
                role: .user,
                metadata: nil,
                parts: [.text(TextUIPart(text: "Hello, world!", state: .streaming))]
            )
        ])
    }

    @Test("returns failure when metadata validation fails")
    func returnsFailureForMetadata() async {
        let result = await safeValidateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "user",
                    "metadata": ["foo": 123],
                    "parts": [
                        ["type": "text", "text": "Hello, world!"]
                    ]
                ]
            ] as [Any],
            metadataSchema: FlexibleSchema(jsonSchema(
                .object([
                    "type": .string("object"),
                    "properties": .object([
                        "foo": .object(["type": .string("string")])
                    ]),
                    "required": .array([.string("foo")]),
                    "additionalProperties": .bool(false)
                ])
            ))
        )

        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("returns failure when tool input invalid")
    func returnsFailureForToolInput() async {
        let tool = Tool(
            inputSchema: stringFooSchema(),
            outputSchema: nil
        )

        let result = await safeValidateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "assistant",
                    "parts": [
                        [
                            "type": "tool-foo",
                            "toolCallId": "1",
                            "state": "input-available",
                            "input": ["foo": 123]
                        ]
                    ]
                ]
            ] as [Any],
            tools: ["foo": tool]
        )

        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("returns failure when data schema missing")
    func returnsFailureForMissingDataSchema() async {
        let result = await safeValidateUIMessages(
            messages: [
                [
                    "id": "1",
                    "role": "assistant",
                    "parts": [
                        ["type": "data-bar", "data": ["foo": "bar"]]
                    ]
                ]
            ] as [Any],
            dataSchemas: [
                "foo": FlexibleSchema(jsonSchema(.object(["type": .string("object")])) )
            ]
        )

        #expect(!result.success)
        #expect(result.error != nil)
    }

    @Test("returns failure for invalid message structure")
    func returnsFailureForInvalidStructure() async {
        let result = await safeValidateUIMessages(messages: [
            ["role": "user"] as [String: Any]
        ])

        #expect(!result.success)
        #expect(result.error != nil)
    }
}

// MARK: - Helpers

private func stringFooSchema() -> FlexibleSchema<JSONValue> {
    FlexibleSchema(jsonSchema(
        .object([
            "type": .string("object"),
            "properties": .object([
                "foo": .object(["type": .string("string")])
            ]),
            "required": .array([.string("foo")]),
            "additionalProperties": .bool(false)
        ])
    ))
}

import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider
import AISDKProviderUtils

private func makeFunctionTool(
    name: String = "testFunction",
    description: String? = nil,
    schema: JSONValue = .object([:]),
    inputExamples: [LanguageModelV3ToolInputExample]? = nil,
    strict: Bool? = nil,
    providerOptions: SharedV3ProviderOptions? = nil
) -> LanguageModelV3Tool {
    .function(LanguageModelV3FunctionTool(
        name: name,
        inputSchema: schema,
        inputExamples: inputExamples,
        description: description,
        strict: strict,
        providerOptions: providerOptions
    ))
}

private func makeProviderTool(
    id: String,
    name: String,
    args: [String: JSONValue] = [:]
) -> LanguageModelV3Tool {
    .provider(LanguageModelV3ProviderTool(id: id, name: name, args: args))
}

@Suite("prepareAnthropicTools basics")
struct AnthropicPrepareToolsBasicTests {
    @Test("returns nil when tools missing")
    func nilTools() async throws {
        let result = try await prepareAnthropicTools(tools: nil, toolChoice: nil, disableParallelToolUse: nil)
        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
        #expect(result.warnings.isEmpty)
        #expect(result.betas.isEmpty)
    }

    @Test("returns nil when tools empty")
    func emptyTools() async throws {
        let result = try await prepareAnthropicTools(tools: [], toolChoice: nil, disableParallelToolUse: nil)
        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
        #expect(result.warnings.isEmpty)
        #expect(result.betas.isEmpty)
    }

    @Test("prepares function tool")
    func preparesFunctionTool() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(name: "testFunction", description: "A test function", schema: .object([:]))],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        let expectedTool = JSONValue.object([
            "name": .string("testFunction"),
            "description": .string("A test function"),
            "input_schema": .object([:])
        ])

        #expect(result.tools == [expectedTool])
        #expect(result.toolChoice == nil)
        #expect(result.warnings.isEmpty)
        #expect(result.betas.isEmpty)
    }

    @Test("preserves tool input examples and adds advanced-tool-use beta")
    func preservesToolInputExamples() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "tool_with_examples",
                description: "tool with examples",
                schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "a": .object(["type": .string("number")])
                    ])
                ]),
                inputExamples: [
                    LanguageModelV3ToolInputExample(input: ["a": .number(1)]),
                    LanguageModelV3ToolInputExample(input: ["a": .number(2)]),
                ]
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13", "advanced-tool-use-2025-11-20"]))

        if case let .object(tool)? = result.tools?.first {
            #expect(tool["name"] == .string("tool_with_examples"))
            #expect(tool["description"] == .string("tool with examples"))
            #expect(tool["input_examples"] == .array([
                .object(["a": .number(1)]),
                .object(["a": .number(2)]),
            ]))
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("sets cache control from provider options")
    func setsCacheControl() async throws {
        let options: SharedV3ProviderOptions = [
            "anthropic": [
                "cacheControl": .object(["type": .string("ephemeral")])
            ]
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(name: "testFunction", description: "Test", schema: .object([:]), providerOptions: options)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )
        let expected = JSONValue.object([
            "name": .string("testFunction"),
            "description": .string("Test"),
            "input_schema": .object([:]),
            "cache_control": .object(["type": .string("ephemeral")])
        ])
        #expect(result.tools == [expected])
    }

    @Test("limits cache breakpoints to 4")
    func limitsCacheBreakpointsTo4() async throws {
        let cacheOptions: SharedV3ProviderOptions = [
            "anthropic": [
                "cacheControl": .object(["type": .string("ephemeral")])
            ]
        ]

        let cacheControlValidator = CacheControlValidator()

        let tools: [LanguageModelV3Tool] = [
            makeFunctionTool(name: "tool1", description: "Test 1", schema: .object([:]), providerOptions: cacheOptions),
            makeFunctionTool(name: "tool2", description: "Test 2", schema: .object([:]), providerOptions: cacheOptions),
            makeFunctionTool(name: "tool3", description: "Test 3", schema: .object([:]), providerOptions: cacheOptions),
            makeFunctionTool(name: "tool4", description: "Test 4", schema: .object([:]), providerOptions: cacheOptions),
            makeFunctionTool(name: "tool5", description: "Test 5 (should be rejected)", schema: .object([:]), providerOptions: cacheOptions),
        ]

        let result = try await prepareAnthropicTools(
            tools: tools,
            toolChoice: nil,
            disableParallelToolUse: nil,
            cacheControlValidator: cacheControlValidator
        )

        guard let prepared = result.tools, prepared.count == 5 else {
            Issue.record("Expected 5 prepared tools")
            return
        }

        for i in 0..<4 {
            if case let .object(tool) = prepared[i] {
                #expect(tool["cache_control"] == .object(["type": .string("ephemeral")]))
            } else {
                Issue.record("Expected tool \(i) to be an object")
            }
        }

        if case let .object(tool5) = prepared[4] {
            #expect(tool5["cache_control"] == nil)
        } else {
            Issue.record("Expected 5th tool to be an object")
        }

        #expect(cacheControlValidator.getWarnings() == [
            .unsupported(
                feature: "cacheControl breakpoint limit",
                details: "Maximum 4 cache breakpoints exceeded (found 5). This breakpoint will be ignored."
            )
        ])
    }

    @Test("supports defer_loading for function tools")
    func supportsDeferLoading() async throws {
        let options: SharedV3ProviderOptions = [
            "anthropic": [
                "deferLoading": .bool(true)
            ]
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(name: "testFunction", schema: .object([:]), providerOptions: options)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )
        if case let .object(tool) = result.tools?.first {
            #expect(tool["defer_loading"] == .bool(true))
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("supports defer_loading false for function tools")
    func supportsDeferLoadingFalse() async throws {
        let options: SharedV3ProviderOptions = [
            "anthropic": [
                "deferLoading": .bool(false)
            ]
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(name: "testFunction", description: "A test function", schema: .object(["type": .string("object"), "properties": .object([:])]), providerOptions: options)],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13"]))
        if case let .object(tool) = result.tools?.first {
            #expect(tool["defer_loading"] == .bool(false))
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("supports allowed_callers and advanced-tool-use beta for function tools")
    func supportsAllowedCallers() async throws {
        let options: SharedV3ProviderOptions = [
            "anthropic": [
                "allowedCallers": .array([.string("code_execution_20250825")])
            ]
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "query_database",
                description: "Query a database",
                schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "sql": .object(["type": .string("string")])
                    ])
                ]),
                providerOptions: options
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13", "advanced-tool-use-2025-11-20"]))
        if case let .object(tool) = result.tools?.first {
            #expect(tool["allowed_callers"] == .array([.string("code_execution_20250825")]))
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("supports defer_loading + allowed_callers together")
    func supportsDeferLoadingAndAllowedCallers() async throws {
        let options: SharedV3ProviderOptions = [
            "anthropic": [
                "deferLoading": .bool(true),
                "allowedCallers": .array([.string("code_execution_20250825")])
            ]
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "query_database",
                description: "Query a database",
                schema: .object([
                    "type": .string("object"),
                    "properties": .object([
                        "sql": .object(["type": .string("string")])
                    ])
                ]),
                providerOptions: options
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13", "advanced-tool-use-2025-11-20"]))
        if case let .object(tool) = result.tools?.first {
            #expect(tool["defer_loading"] == .bool(true))
            #expect(tool["allowed_callers"] == .array([.string("code_execution_20250825")]))
        } else {
            Issue.record("Expected tool object")
        }
    }
}

@Suite("prepareAnthropicTools strict mode")
struct AnthropicPrepareToolsStrictModeTests {
    @Test("includes strict and beta when supportsStructuredOutput is true and strict is true")
    func strictTrueWithStructuredOutput() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "testFunction",
                description: "A test function",
                schema: .object(["type": .string("object"), "properties": .object([:])]),
                strict: true
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13"]))
        if case let .object(tool)? = result.tools?.first {
            #expect(tool["strict"] == .bool(true))
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("includes beta but not strict when strict is nil and supportsStructuredOutput is true")
    func strictNilWithStructuredOutput() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "testFunction",
                description: "A test function",
                schema: .object(["type": .string("object"), "properties": .object([:])])
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13"]))
        if case let .object(tool)? = result.tools?.first {
            #expect(tool["strict"] == nil)
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("does not include strict or beta when supportsStructuredOutput is false")
    func strictTrueWithoutStructuredOutput() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "testFunction",
                description: "A test function",
                schema: .object(["type": .string("object"), "properties": .object([:])]),
                strict: true
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: false
        )

        #expect(result.betas.isEmpty)
        if case let .object(tool)? = result.tools?.first {
            #expect(tool["strict"] == nil)
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("includes beta and strict false when supportsStructuredOutput is true")
    func strictFalseWithStructuredOutput() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(
                name: "testFunction",
                description: "A test function",
                schema: .object(["type": .string("object"), "properties": .object([:])]),
                strict: false
            )],
            toolChoice: nil,
            disableParallelToolUse: nil,
            supportsStructuredOutput: true
        )

        #expect(result.betas == Set(["structured-outputs-2025-11-13"]))
        if case let .object(tool)? = result.tools?.first {
            #expect(tool["strict"] == .bool(false))
        } else {
            Issue.record("Expected tool object")
        }
    }
}

	@Suite("prepareAnthropicTools provider defined")
struct AnthropicPrepareToolsProviderDefinedTests {
    @Test("computer_20241022 adds beta and payload")
    func computer20241022() async throws {
        let args: [String: JSONValue] = [
            "displayWidthPx": .number(800),
            "displayHeightPx": .number(600),
            "displayNumber": .number(1)
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.computer_20241022", name: "computer", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        let expected = JSONValue.object([
            "name": .string("computer"),
            "type": .string("computer_20241022"),
            "display_width_px": .number(800),
            "display_height_px": .number(600),
            "display_number": .number(1)
        ])

        #expect(result.tools == [expected])
        #expect(result.betas == Set(["computer-use-2024-10-22"]))
    }

    @Test("computer_20251124 adds beta and payload")
    func computer20251124() async throws {
        let args: [String: JSONValue] = [
            "displayWidthPx": .number(1024),
            "displayHeightPx": .number(768),
            "displayNumber": .number(1),
            "enableZoom": .bool(true),
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.computer_20251124", name: "computer", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        let expected = JSONValue.object([
            "name": .string("computer"),
            "type": .string("computer_20251124"),
            "display_width_px": .number(1024),
            "display_height_px": .number(768),
            "display_number": .number(1),
            "enable_zoom": .bool(true),
        ])

        #expect(result.tools == [expected])
        #expect(result.betas == Set(["computer-use-2025-11-24"]))
    }

    @Test("computer_20251124 omits enable_zoom when not provided")
    func computer20251124WithoutEnableZoom() async throws {
        let args: [String: JSONValue] = [
            "displayWidthPx": .number(1024),
            "displayHeightPx": .number(768),
            "displayNumber": .number(1),
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.computer_20251124", name: "computer", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        let expected = JSONValue.object([
            "name": .string("computer"),
            "type": .string("computer_20251124"),
            "display_width_px": .number(1024),
            "display_height_px": .number(768),
            "display_number": .number(1),
        ])

        #expect(result.tools == [expected])
        #expect(result.betas == Set(["computer-use-2025-11-24"]))
    }

    @Test("computer_20251124 supports enable_zoom false")
    func computer20251124EnableZoomFalse() async throws {
        let args: [String: JSONValue] = [
            "displayWidthPx": .number(1024),
            "displayHeightPx": .number(768),
            "displayNumber": .number(1),
            "enableZoom": .bool(false),
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.computer_20251124", name: "computer", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        let expected = JSONValue.object([
            "name": .string("computer"),
            "type": .string("computer_20251124"),
            "display_width_px": .number(1024),
            "display_height_px": .number(768),
            "display_number": .number(1),
            "enable_zoom": .bool(false),
        ])

        #expect(result.tools == [expected])
        #expect(result.betas == Set(["computer-use-2025-11-24"]))
    }

    @Test("computer_20250124 adds beta and payload")
    func computer20250124() async throws {
        let args: [String: JSONValue] = [
            "displayWidthPx": .number(1024),
            "displayHeightPx": .number(768),
            "displayNumber": .number(1),
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.computer_20250124", name: "computer", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        let expected = JSONValue.object([
            "name": .string("computer"),
            "type": .string("computer_20250124"),
            "display_width_px": .number(1024),
            "display_height_px": .number(768),
            "display_number": .number(1),
        ])

        #expect(result.tools == [expected])
        #expect(result.betas == Set(["computer-use-2025-01-24"]))
    }

    @Test("text_editor_20250728 handles max characters")
    func textEditor20250728WithMax() async throws {
        let args: [String: JSONValue] = ["maxCharacters": .number(10_000)]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.text_editor_20250728", name: "str_replace_based_edit_tool", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(result.betas.isEmpty)
        if case let .object(tool) = result.tools?.first {
            #expect(tool["type"] == .string("text_editor_20250728"))
            #expect(tool["name"] == .string("str_replace_based_edit_tool"))
            #expect(tool["max_characters"] == .number(10_000))
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("text_editor_20250728 without max characters")
    func textEditor20250728WithoutMax() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.text_editor_20250728", name: "str_replace_based_edit_tool")],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(result.betas.isEmpty)
        if case let .object(tool) = result.tools?.first {
            #expect(tool["type"] == .string("text_editor_20250728"))
            #expect(tool["name"] == .string("str_replace_based_edit_tool"))
            #expect(tool.keys.contains("max_characters") == false || tool["max_characters"] == .null)
        } else {
            Issue.record("Expected tool object")
        }
    }

    @Test("web_search_20250305 parses args")
    func webSearch20250305() async throws {
        let args: [String: JSONValue] = [
            "maxUses": .number(10),
            "allowedDomains": .array([.string("https://www.google.com")]),
            "userLocation": .object([
                "type": .string("approximate"),
                "city": .string("New York")
            ])
        ]
        let result = try await prepareAnthropicTools(
            tools: [makeProviderTool(id: "anthropic.web_search_20250305", name: "web_search", args: args)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )
        #expect(result.betas.isEmpty)
        if case let .object(tool) = result.tools?.first {
            #expect(tool["type"] == .string("web_search_20250305"))
            #expect(tool["name"] == .string("web_search"))
            #expect(tool["max_uses"] == .number(10))
            #expect(tool["allowed_domains"] == .array([.string("https://www.google.com")]))
            if case let .object(location)? = tool["user_location"] {
                #expect(location["type"] == .string("approximate"))
                #expect(location["city"] == .string("New York"))
            } else {
                Issue.record("Expected user_location")
            }
        } else {
            Issue.record("Expected tool object")
        }
    }

	    @Test("web_fetch_20250910 parses args and betas")
    func webFetch20250910() async throws {
	        let args: [String: JSONValue] = [
	            "maxUses": .number(10),
	            "allowedDomains": .array([.string("https://www.google.com")]),
	            "citations": .object(["enabled": .bool(true)]),
	            "maxContentTokens": .number(1_000)
	        ]
	        let result = try await prepareAnthropicTools(
	            tools: [makeProviderTool(id: "anthropic.web_fetch_20250910", name: "web_fetch", args: args)],
	            toolChoice: nil,
	            disableParallelToolUse: nil
	        )
	        #expect(result.betas == Set(["web-fetch-2025-09-10"]))
	        if case let .object(tool) = result.tools?.first {
	            #expect(tool["type"] == .string("web_fetch_20250910"))
	            #expect(tool["name"] == .string("web_fetch"))
	            #expect(tool["max_uses"] == .number(10))
	            #expect(tool["allowed_domains"] == .array([.string("https://www.google.com")]))
	            #expect(tool["citations"] == .object(["enabled": .bool(true)]))
	            #expect(tool["max_content_tokens"] == .number(1_000))
	        } else {
	            Issue.record("Expected web_fetch tool object")
	        }
	    }

	    @Test("tool_search_regex_20251119 adds beta and payload")
	    func toolSearchRegex20251119() async throws {
	        let result = try await prepareAnthropicTools(
	            tools: [makeProviderTool(id: "anthropic.tool_search_regex_20251119", name: "tool_search_tool_regex")],
	            toolChoice: nil,
	            disableParallelToolUse: nil
	        )

	        #expect(result.betas == Set(["advanced-tool-use-2025-11-20"]))
	        #expect(result.tools == [
	            .object([
	                "type": .string("tool_search_tool_regex_20251119"),
	                "name": .string("tool_search_tool_regex"),
	            ])
	        ])
	    }

	    @Test("tool_search_bm25_20251119 adds beta and payload")
	    func toolSearchBm2520251119() async throws {
	        let result = try await prepareAnthropicTools(
	            tools: [makeProviderTool(id: "anthropic.tool_search_bm25_20251119", name: "tool_search_tool_bm25")],
	            toolChoice: nil,
	            disableParallelToolUse: nil
	        )

	        #expect(result.betas == Set(["advanced-tool-use-2025-11-20"]))
	        #expect(result.tools == [
	            .object([
	                "type": .string("tool_search_tool_bm25_20251119"),
	                "name": .string("tool_search_tool_bm25"),
	            ])
	        ])
	    }

	    @Test("unsupported provider tool yields warning")
	    func unsupportedProviderTool() async throws {
	        let unsupported = makeProviderTool(id: "unsupported.tool", name: "unsupported_tool")
	        let result = try await prepareAnthropicTools(
	            tools: [unsupported],
	            toolChoice: nil,
	            disableParallelToolUse: nil
	        )

        #expect(result.tools == [])
        #expect(result.toolChoice == nil)
        #expect(result.warnings == [.unsupported(feature: "provider-defined tool unsupported.tool", details: nil)])
    }

    @Test("Anthropic tool wrappers: web_search_20250305 forwards options")
    func wrapperWebSearch20250305() async throws {
        let tool = anthropicWebSearch20250305(
            .init(
                maxUses: 10,
                allowedDomains: ["https://www.google.com"],
                userLocation: .init(city: "New York")
            )
        )

        guard let id = tool.id, let name = tool.name else {
            Issue.record("Expected provider tool id/name")
            return
        }

        let providerTool = LanguageModelV3ProviderTool(id: id, name: name, args: tool.args ?? [:])

        let prepared = try await prepareAnthropicTools(
            tools: [.provider(providerTool)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(prepared.betas.isEmpty)
        if case let .object(payload)? = prepared.tools?.first {
            #expect(payload["type"] == .string("web_search_20250305"))
            #expect(payload["name"] == .string("web_search"))
            #expect(payload["max_uses"] == .number(10))
            #expect(payload["allowed_domains"] == .array([.string("https://www.google.com")]))
            if case let .object(location)? = payload["user_location"] {
                #expect(location["type"] == .string("approximate"))
                #expect(location["city"] == .string("New York"))
            } else {
                Issue.record("Expected user_location")
            }
        } else {
            Issue.record("Expected prepared tool payload")
        }
    }

    @Test("Anthropic tool wrappers: computer_20241022 forwards display settings")
    func wrapperComputer20241022() async throws {
        let tool = anthropicComputer20241022(.init(displayWidthPx: 800, displayHeightPx: 600, displayNumber: 1))

        guard let id = tool.id, let name = tool.name else {
            Issue.record("Expected provider tool id/name")
            return
        }

        let providerTool = LanguageModelV3ProviderTool(id: id, name: name, args: tool.args ?? [:])

        let prepared = try await prepareAnthropicTools(
            tools: [.provider(providerTool)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(prepared.betas == Set(["computer-use-2024-10-22"]))
        if case let .object(payload)? = prepared.tools?.first {
            #expect(payload["type"] == .string("computer_20241022"))
            #expect(payload["name"] == .string("computer"))
            #expect(payload["display_width_px"] == .number(800))
            #expect(payload["display_height_px"] == .number(600))
            #expect(payload["display_number"] == .number(1))
        } else {
            Issue.record("Expected prepared tool payload")
        }
    }

    @Test("Anthropic tool wrappers: computer_20250124 forwards display settings")
    func wrapperComputer20250124() async throws {
        let tool = anthropicComputer20250124(.init(displayWidthPx: 1024, displayHeightPx: 768, displayNumber: 1))

        guard let id = tool.id, let name = tool.name else {
            Issue.record("Expected provider tool id/name")
            return
        }

        let providerTool = LanguageModelV3ProviderTool(id: id, name: name, args: tool.args ?? [:])

        let prepared = try await prepareAnthropicTools(
            tools: [.provider(providerTool)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(prepared.betas == Set(["computer-use-2025-01-24"]))
        if case let .object(payload)? = prepared.tools?.first {
            #expect(payload["type"] == .string("computer_20250124"))
            #expect(payload["name"] == .string("computer"))
            #expect(payload["display_width_px"] == .number(1024))
            #expect(payload["display_height_px"] == .number(768))
            #expect(payload["display_number"] == .number(1))
        } else {
            Issue.record("Expected prepared tool payload")
        }
    }

    @Test("Anthropic tool wrappers: computer_20251124 forwards enableZoom")
    func wrapperComputer20251124() async throws {
        let tool = anthropicComputer20251124(.init(displayWidthPx: 1024, displayHeightPx: 768, displayNumber: 1, enableZoom: true))

        guard let id = tool.id, let name = tool.name else {
            Issue.record("Expected provider tool id/name")
            return
        }

        let providerTool = LanguageModelV3ProviderTool(id: id, name: name, args: tool.args ?? [:])

        let prepared = try await prepareAnthropicTools(
            tools: [.provider(providerTool)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(prepared.betas == Set(["computer-use-2025-11-24"]))
        if case let .object(payload)? = prepared.tools?.first {
            #expect(payload["type"] == .string("computer_20251124"))
            #expect(payload["name"] == .string("computer"))
            #expect(payload["display_width_px"] == .number(1024))
            #expect(payload["display_height_px"] == .number(768))
            #expect(payload["display_number"] == .number(1))
            #expect(payload["enable_zoom"] == .bool(true))
        } else {
            Issue.record("Expected prepared tool payload")
        }
    }

    @Test("Anthropic tool wrappers: web_fetch_20250910 forwards options")
    func wrapperWebFetch20250910() async throws {
        let tool = anthropicWebFetch20250910(
            .init(
                maxUses: 10,
                allowedDomains: ["https://www.google.com"],
                citationsEnabled: true,
                maxContentTokens: 1_000
            )
        )

        guard let id = tool.id, let name = tool.name else {
            Issue.record("Expected provider tool id/name")
            return
        }

        let providerTool = LanguageModelV3ProviderTool(id: id, name: name, args: tool.args ?? [:])

        let prepared = try await prepareAnthropicTools(
            tools: [.provider(providerTool)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(prepared.betas == Set(["web-fetch-2025-09-10"]))
        if case let .object(payload)? = prepared.tools?.first {
            #expect(payload["type"] == .string("web_fetch_20250910"))
            #expect(payload["name"] == .string("web_fetch"))
            #expect(payload["max_uses"] == .number(10))
            #expect(payload["allowed_domains"] == .array([.string("https://www.google.com")]))
            #expect(payload["citations"] == .object(["enabled": .bool(true)]))
            #expect(payload["max_content_tokens"] == .number(1_000))
        } else {
            Issue.record("Expected prepared tool payload")
        }
    }

    @Test("Anthropic tool wrappers: text_editor_20250728 forwards maxCharacters")
    func wrapperTextEditor20250728() async throws {
        let tool = anthropicTextEditor20250728(.init(maxCharacters: 10_000))

        guard let id = tool.id, let name = tool.name else {
            Issue.record("Expected provider tool id/name")
            return
        }

        let providerTool = LanguageModelV3ProviderTool(id: id, name: name, args: tool.args ?? [:])

        let prepared = try await prepareAnthropicTools(
            tools: [.provider(providerTool)],
            toolChoice: nil,
            disableParallelToolUse: nil
        )

        #expect(prepared.betas.isEmpty)
        if case let .object(payload)? = prepared.tools?.first {
            #expect(payload["type"] == .string("text_editor_20250728"))
            #expect(payload["name"] == .string("str_replace_based_edit_tool"))
            #expect(payload["max_characters"] == .number(10_000))
        } else {
            Issue.record("Expected prepared tool payload")
        }
    }
}

@Suite("prepareAnthropicTools tool choice")
struct AnthropicPrepareToolsChoiceTests {
    @Test("auto choice propagates")
    func autoChoice() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool()],
            toolChoice: .auto,
            disableParallelToolUse: nil
        )
        #expect(result.toolChoice == .object(["type": .string("auto")]))
    }

    @Test("required choice maps to any")
    func requiredChoice() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool()],
            toolChoice: .required,
            disableParallelToolUse: nil
        )
        #expect(result.toolChoice == .object(["type": .string("any")]))
    }

    @Test("none choice clears tools")
    func noneChoice() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool()],
            toolChoice: .some(.none),
            disableParallelToolUse: nil
        )
        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
    }

    @Test("tool choice names tool")
    func toolChoice() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool(name: "testFunction")],
            toolChoice: .tool(toolName: "testFunction"),
            disableParallelToolUse: nil
        )
        #expect(result.toolChoice == .object([
            "type": .string("tool"),
            "name": .string("testFunction")
        ]))
    }

    @Test("auto choice respects disableParallelToolUse")
    func disableParallelToolUseAuto() async throws {
        let result = try await prepareAnthropicTools(
            tools: [makeFunctionTool()],
            toolChoice: nil,
            disableParallelToolUse: true
        )
        #expect(result.toolChoice == .object([
            "type": .string("auto"),
            "disable_parallel_tool_use": .bool(true)
        ]))
    }
}

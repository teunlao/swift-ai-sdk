import Foundation
import Testing
@testable import AnthropicProvider
import AISDKProvider

private func makeFunctionTool(
    name: String = "testFunction",
    description: String? = nil,
    schema: JSONValue = .object([:]),
    providerOptions: SharedV3ProviderOptions? = nil
) -> LanguageModelV3Tool {
    .function(LanguageModelV3FunctionTool(
        name: name,
        inputSchema: schema,
        description: description,
        providerOptions: providerOptions
    ))
}

private func makeProviderTool(
    id: String,
    name: String,
    args: [String: JSONValue] = [:]
) -> LanguageModelV3Tool {
    .providerDefined(LanguageModelV3ProviderDefinedTool(id: id, name: name, args: args))
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
}

	@Suite("prepareAnthropicTools provider defined")
	struct AnthropicPrepareToolsProviderDefinedTests {
    @Test("computer_20241022 adds beta and payload")
    func computer20241022() async throws {
        let args: [String: JSONValue] = [
            "display_width_px": .number(800),
            "display_height_px": .number(600),
            "display_number": .number(1)
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
            "display_width_px": .number(1024),
            "display_height_px": .number(768),
            "display_number": .number(1),
            "enable_zoom": .bool(true),
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

        #expect(result.tools == nil)
        #expect(result.toolChoice == nil)
        #expect(result.warnings == [.unsupportedTool(tool: unsupported, details: nil)])
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

import Foundation
import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

private let basePrompt: LanguageModelV3Prompt = [
    .user(content: [.text(.init(text: "Hello, world!"))], providerOptions: nil)
]

private func makeBaseOptions(tools: [LanguageModelV3Tool]?) -> LanguageModelV3CallOptions {
    LanguageModelV3CallOptions(
        prompt: basePrompt,
        tools: tools
    )
}

private func makeFunctionTool(
    name: String,
    description: String? = nil,
    inputExamples: [LanguageModelV3ToolInputExample]? = nil
) -> LanguageModelV3Tool {
    .function(LanguageModelV3FunctionTool(
        name: name,
        inputSchema: .object([
            "type": .string("object"),
            "properties": .object([:])
        ]),
        inputExamples: inputExamples,
        description: description
    ))
}

private func transform(
    _ middleware: LanguageModelV3Middleware,
    _ options: LanguageModelV3CallOptions
) async throws -> LanguageModelV3CallOptions {
    guard let transform = middleware.transformParams else {
        Issue.record("Expected transformParams to be set")
        return options
    }
    return try await transform(.generate, options, MockLanguageModelV3())
}

@Suite("addToolInputExamplesMiddleware")
struct AddToolInputExamplesMiddlewareTests {
    @Suite("transformParams")
    struct TransformParamsTests {
        @Test("appends examples to tool description")
        func appendsExamples() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather in a location",
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("San Francisco")]),
                            LanguageModelV3ToolInputExample(input: ["location": .string("London")]),
                        ]
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == """
Get the weather in a location

Input Examples:
{\"location\":\"San Francisco\"}
{\"location\":\"London\"}
""")
                #expect(tool.inputExamples == nil)
            } else {
                Issue.record("Expected function tool")
            }
        }

        @Test("handles tool without existing description")
        func noExistingDescription() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: nil,
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("Berlin")]),
                        ]
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == """
Input Examples:
{\"location\":\"Berlin\"}
""")
                #expect(tool.inputExamples == nil)
            } else {
                Issue.record("Expected function tool")
            }
        }
    }

    @Suite("prefix")
    struct PrefixTests {
        @Test("uses provided prefix")
        func usesPrefix() async throws {
            let middleware = addToolInputExamplesMiddleware(options: AddToolInputExamplesOptions(
                prefix: "Here are some example inputs:"
            ))

            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather",
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("Paris")]),
                        ]
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == """
Get the weather

Here are some example inputs:
{\"location\":\"Paris\"}
""")
            } else {
                Issue.record("Expected function tool")
            }
        }
    }

    @Suite("format")
    struct FormatTests {
        @Test("uses default JSON stringify format")
        func defaultFormat() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    .function(LanguageModelV3FunctionTool(
                        name: "search",
                        inputSchema: .object([
                            "type": .string("object"),
                            "properties": .object([
                                "query": .object(["type": .string("string")]),
                                "limit": .object(["type": .string("number")]),
                            ])
                        ]),
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: [
                                "query": .string("test"),
                                "limit": .number(10),
                            ])
                        ],
                        description: "Search for items"
                    ))
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == """
Search for items

Input Examples:
{\"limit\":10,\"query\":\"test\"}
""")
            } else {
                Issue.record("Expected function tool")
            }
        }

        @Test("uses custom format function")
        func customFormat() async throws {
            let middleware = addToolInputExamplesMiddleware(options: AddToolInputExamplesOptions(
                format: { example, index in
                    let encoder = JSONEncoder()
                    guard let data = try? encoder.encode(JSONValue.object(example.input)) else {
                        return "\(index + 1). {}"
                    }
                    return "\(index + 1). \(String(decoding: data, as: UTF8.self))"
                }
            ))

            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather",
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("Paris")]),
                            LanguageModelV3ToolInputExample(input: ["location": .string("Tokyo")]),
                        ]
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == """
Get the weather

Input Examples:
1. {\"location\":\"Paris\"}
2. {\"location\":\"Tokyo\"}
""")
            } else {
                Issue.record("Expected function tool")
            }
        }
    }

    @Suite("remove")
    struct RemoveTests {
        @Test("removes inputExamples by default")
        func removesByDefault() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather",
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("NYC")]),
                        ]
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.inputExamples == nil)
            } else {
                Issue.record("Expected function tool")
            }
        }

        @Test("keeps inputExamples when remove is false")
        func keepsWhenRemoveFalse() async throws {
            let middleware = addToolInputExamplesMiddleware(options: AddToolInputExamplesOptions(remove: false))
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather",
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("NYC")]),
                        ]
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.inputExamples == [
                    LanguageModelV3ToolInputExample(input: ["location": .string("NYC")])
                ])
            } else {
                Issue.record("Expected function tool")
            }
        }
    }

    @Suite("edge cases")
    struct EdgeCaseTests {
        @Test("passes through tools without inputExamples")
        func noInputExamples() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [makeFunctionTool(name: "weather", description: "Get the weather")])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == "Get the weather")
            } else {
                Issue.record("Expected function tool")
            }
        }

        @Test("passes through tools with empty inputExamples array")
        func emptyInputExamples() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather",
                        inputExamples: []
                    )
                ])
            )

            if case .function(let tool) = result.tools?.first {
                #expect(tool.description == "Get the weather")
            } else {
                Issue.record("Expected function tool")
            }
        }

        @Test("passes through provider tools unchanged")
        func providerToolsUnchanged() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let providerTool = LanguageModelV3ProviderTool(
                id: "anthropic.web_search_20250305",
                name: "web_search",
                args: ["maxUses": .number(5)]
            )
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [.provider(providerTool)])
            )

            if case .provider(let tool) = result.tools?.first {
                #expect(tool.id == "anthropic.web_search_20250305")
                #expect(tool.name == "web_search")
                #expect(tool.args["maxUses"] == .number(5))
            } else {
                Issue.record("Expected provider tool")
            }
        }

        @Test("handles multiple tools with mixed examples")
        func mixedExamples() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(
                middleware,
                makeBaseOptions(tools: [
                    makeFunctionTool(
                        name: "weather",
                        description: "Get the weather",
                        inputExamples: [
                            LanguageModelV3ToolInputExample(input: ["location": .string("NYC")]),
                        ]
                    ),
                    makeFunctionTool(name: "time", description: "Get the current time")
                ])
            )

            #expect(result.tools?.count == 2)

            if case .function(let weather) = result.tools?[0],
               case .function(let time) = result.tools?[1] {
                #expect(weather.description?.contains("Input Examples:") == true)
                #expect(time.description == "Get the current time")
            } else {
                Issue.record("Expected two function tools")
            }
        }

        @Test("handles empty tools array")
        func emptyToolsArray() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(middleware, makeBaseOptions(tools: []))
            #expect(result.tools == [])
        }

        @Test("handles nil tools")
        func nilTools() async throws {
            let middleware = addToolInputExamplesMiddleware()
            let result = try await transform(middleware, makeBaseOptions(tools: nil))
            #expect(result.tools == nil)
        }
    }
}

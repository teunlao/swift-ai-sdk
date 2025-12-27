/**
 JSON Schema Auto Generation Example

 Demonstrates automatic schema generation with FlexibleSchema.auto() for:
 - generateObject() - structured object generation
 - streamObject() - streaming structured objects
 - tool() - function calling with typed inputs

 Uses Foundation types (Date, URL, Data), enums, nested objects, and arrays.
 */

import AISDKJSONSchema
import AISDKProvider
import AISDKProviderUtils
import ExamplesCore
import Foundation
import OpenAIProvider
import SwiftAISDK

// MARK: - Example Types

/// Task priority enum - will generate {"type": "string", "enum": [...]}
enum TaskPriority: String, Codable, Sendable, CaseIterable {
    case low, medium, high, urgent
}

/// Task status enum
enum TaskStatus: String, Codable, Sendable, CaseIterable {
    case todo, inProgress, done, blocked
}

/// Task type for generateObject and tool examples
struct Task: Codable, Sendable {
    let title: String
    let description: String
    let priority: TaskPriority
    let status: TaskStatus
    let dueDate: Date
    let assignee: String
    let tags: [String]
}

/// Blog post with nested author and Foundation types
struct BlogPost: Codable, Sendable {
    let title: String
    let content: String
    let author: Author
    let publishedAt: Date
    let updatedAt: Date?
    let tags: [String]
    let viewCount: Int
    let featured: Bool
}

struct Author: Codable, Sendable {
    let name: String
    let email: String
    let website: URL
    let bio: String
}

/// Recipe with nested ingredients - for streamObject example
struct Recipe: Codable, Sendable {
    let name: String
    let description: String
    let prepTime: Int
    let cookTime: Int
    let servings: Int
    let difficulty: String
    let ingredients: [Ingredient]
    let steps: [String]
    let tags: [String]
}

struct Ingredient: Codable, Sendable {
    let name: String
    let amount: String
    let unit: String?
}

/// Search parameters - for tool example
struct SearchParams: Codable, Sendable {
    let query: String
    let maxResults: Int
    let category: String?
    let sortBy: SortOrder
}

enum SortOrder: String, Codable, Sendable, CaseIterable {
    case relevance, date, popularity
}

// MARK: - Main Example

@main
struct JSONSchemaAutoExample: CLIExample {
    static let name = "JSON Schema Auto Generation (.auto())"
    static let description = "Automatic schema generation for all schema-accepting APIs"

    static func run() async throws {
        // Example 1: generateObject with .auto()
        try await example1_generateObject()

        Logger.separator()
        Logger.separator()

        // Example 2: streamObject with .auto()
        try await example2_streamObject()

        Logger.separator()
        Logger.separator()

        // Example 3: tool with .auto() inputSchema
        try await example3_toolWithAuto()
    }

    // MARK: - Example 1: generateObject

    static func example1_generateObject() async throws {
        Logger.section("Example 1: generateObject with .auto()")
        Logger.info("Generating BlogPost with nested Author, Date, URL, enums...")

        // Generate schema and log it
        let schema = FlexibleSchema.auto(BlogPost.self)
        let resolvedSchema = try await schema.resolve().jsonSchema()
        Logger.separator()
        Logger.info("Generated JSON Schema:")
        Helpers.printJSON(resolvedSchema)
        Logger.separator()

        let result = try await generateObject(
            model: openai("gpt-5"),
            schema: schema,
            prompt: """
                Generate a blog post about Swift AI SDK.
                Author: John Doe (john@example.com, https://johndoe.dev)
                Include 3-4 tags, make it featured, view count around 1000.
                """,
            schemaName: "blogPost",
            schemaDescription: "A blog post with author information",
            providerOptions: ["openai": ["reasoningEffort": .string("low")]]
        )

        let post: BlogPost = result.object

        Logger.success("✅ Generated BlogPost:")
        Logger.info("  Title: \(post.title)")
        Logger.info("  Author: \(post.author.name) (\(post.author.email))")
        Logger.info("  Website: \(post.author.website)")
        Logger.info("  Published: \(formatDate(post.publishedAt))")
        Logger.info("  Updated: \(post.updatedAt.map(formatDate) ?? "N/A")")
        Logger.info("  Tags: \(post.tags.joined(separator: ", "))")
        Logger.info("  Views: \(post.viewCount)")
        Logger.info("  Featured: \(post.featured)")
        Logger.info("  Content preview: \(String(post.content.prefix(100)))...")

        Logger.separator()
        Logger.info("Tokens used: \(result.usage.totalTokens ?? 0)")
        Logger.info("Finish reason: \(result.finishReason)")
    }

    // MARK: - Example 2: streamObject

    static func example2_streamObject() async throws {
        Logger.section("Example 2: streamObject with .auto()")
        Logger.info("Streaming Recipe with nested Ingredient array...")

        let stream = try streamObject(
            model: openai("gpt-4o"),
            schema: Recipe.self,
            prompt: "Generate a recipe for chocolate chip cookies",
            schemaName: "recipe",
            schemaDescription: "A detailed recipe with ingredients and steps"
        )

        var ingredientCount = 0
        var stepCount = 0
        var chunkCount = 0

        for try await partialDict in stream.partialObjectStream {
            chunkCount += 1
            Logger.info("📦 Chunk #\(chunkCount): \(partialDict.keys.joined(separator: ", "))")

            // Track ingredients progress
            if case .array(let ingredientsArray) = partialDict["ingredients"] {
                let newCount = ingredientsArray.count
                if newCount > ingredientCount {
                    ingredientCount = newCount
                    Logger.info("📝 Ingredients: \(newCount)")
                }
            }

            // Track steps progress
            if case .array(let stepsArray) = partialDict["steps"] {
                let newCount = stepsArray.count
                if newCount > stepCount {
                    stepCount = newCount
                    Logger.info("🔧 Steps: \(newCount)")
                }
            }
        }

        // Wait for final object
        let recipe = try await stream.object
        let usage = try await stream.usage
        let finishReason = try await stream.finishReason

        Logger.separator()
        Logger.success("✅ Complete Recipe:")
        Logger.info("  Name: \(recipe.name)")
        Logger.info("  Description: \(recipe.description)")
        Logger.info("  Prep: \(recipe.prepTime)min, Cook: \(recipe.cookTime)min")
        Logger.info("  Servings: \(recipe.servings), Difficulty: \(recipe.difficulty)")
        Logger.info("  Ingredients: \(recipe.ingredients.count)")
        for (i, ing) in recipe.ingredients.enumerated() {
            Logger.info("    \(i+1). \(ing.amount) \(ing.unit ?? "") \(ing.name)")
        }
        Logger.info("  Steps: \(recipe.steps.count)")
        for (i, step) in recipe.steps.enumerated() {
            Logger.info("    \(i+1). \(step)")
        }
        Logger.info("  Tags: \(recipe.tags.joined(separator: ", "))")

        Logger.separator()
        Logger.info("Tokens used: \(usage.totalTokens ?? 0)")
        Logger.info("Finish reason: \(finishReason)")
        Logger.info("Chunks received: \(chunkCount)")
    }

    // MARK: - Example 3: tool with .auto()

    static func example3_toolWithAuto() async throws {
        Logger.section("Example 3: tool() with .auto() inputSchema")
        Logger.info("Creating search tool with typed parameters...")

        // Define tool with .auto() for inputSchema
        // Note: tool() requires FlexibleSchema<JSONValue>, so we generate schema with .auto()
        // and wrap it in FlexibleSchema(jsonSchema:)
        let searchParamsSchema = FlexibleSchema.auto(SearchParams.self)
        let searchParamsJSONSchema = try await searchParamsSchema.resolve().jsonSchema()

        let searchTool = tool(
            description: "Search for content with filters",
            inputSchema: FlexibleSchema(jsonSchema(searchParamsJSONSchema)),
            execute: { (input: JSONValue, _) async throws -> ToolExecutionResult<JSONValue> in
                Logger.info("🔍 Search tool called with input: \(input)")

                // Parse JSONValue manually
                guard case .object(let obj) = input,
                    case .string(let query) = obj["query"] ?? .null,
                    case .number(let maxResults) = obj["maxResults"] ?? .null,
                    case .string(let sortByRaw) = obj["sortBy"] ?? .null
                else {
                    return .value(.string("Invalid input parameters"))
                }

                let category: String? = {
                    if case .string(let cat) = obj["category"] {
                        return cat
                    }
                    return nil
                }()

                Logger.success("🔍 Parsed parameters:")
                Logger.info("  Query: \(query)")
                Logger.info("  Max results: \(Int(maxResults))")
                Logger.info("  Category: \(category ?? "all")")
                Logger.info("  Sort by: \(sortByRaw)")

                // Simulate search results
                let results = [
                    "Result 1: Swift AI SDK Documentation",
                    "Result 2: Getting Started Guide",
                    "Result 3: API Reference",
                ]

                return .value(
                    .object([
                        "query": .string(query),
                        "results": .array(results.prefix(Int(maxResults)).map { .string($0) }),
                        "totalFound": .number(Double(results.count)),
                        "category": category.map { .string($0) } ?? .null,
                    ]))
            }
        )

        // Use the tool
        let result = try await generateText(
            model: openai("gpt-4o"),
            tools: ["search": searchTool],
            prompt: """
                Search for "Swift AI SDK" documentation, get top 2 results,
                sort by relevance, category should be "docs"
                """
        )

        Logger.separator()
        Logger.info("Result: \(result.text)")

        if !result.toolCalls.isEmpty {
            Logger.separator()
            Logger.info("Tool calls made: \(result.toolCalls.count)")
            for toolCall in result.toolCalls {
                Logger.info("  - \(toolCall.toolName):")
                Helpers.printJSON(toolCall.input)
            }
        }

        if !result.toolResults.isEmpty {
            Logger.separator()
            Logger.info("Tool results:")
            for toolResult in result.toolResults {
                Logger.info("  - \(toolResult.toolName):")
                Helpers.printJSON(toolResult.output)
            }
        }

        Logger.separator()
        Logger.info("Tokens used: \(result.usage.totalTokens ?? 0)")
    }

    // MARK: - Helpers

    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAIResponsesPreparedTools: Sendable {
    let tools: [JSONValue]?
    let toolChoice: JSONValue?
    let warnings: [LanguageModelV3CallWarning]
}

func prepareOpenAIResponsesTools(
    tools: [LanguageModelV3Tool]?,
    toolChoice: LanguageModelV3ToolChoice?,
    strictJsonSchema: Bool
) async throws -> OpenAIResponsesPreparedTools {
    guard let tools, !tools.isEmpty else {
        return OpenAIResponsesPreparedTools(tools: nil, toolChoice: nil, warnings: [])
    }

    var warnings: [LanguageModelV3CallWarning] = []
    var openAITools: [JSONValue] = []

    for tool in tools {
        switch tool {
        case .function(let functionTool):
            var payload: [String: JSONValue] = [
                "type": .string("function"),
                "name": .string(functionTool.name),
                "parameters": functionTool.inputSchema,
                "strict": .bool(strictJsonSchema)
            ]
            if let description = functionTool.description {
                payload["description"] = .string(description)
            }
            openAITools.append(.object(payload))

        case .providerDefined(let providerTool):
            switch providerTool.id {
            case "openai.file_search":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiFileSearchArgsSchema)
                )
                let rankingOptions: JSONValue?
                if let ranking = parsed.ranking {
                    var rankingPayload: [String: JSONValue] = [:]
                    if let ranker = ranking.ranker {
                        rankingPayload["ranker"] = .string(ranker)
                    }
                    if let threshold = ranking.scoreThreshold {
                        rankingPayload["score_threshold"] = .number(threshold)
                    }
                    rankingOptions = rankingPayload.isEmpty ? nil : .object(rankingPayload)
                } else {
                    rankingOptions = nil
                }

                var payload: [String: JSONValue] = [
                    "type": .string("file_search"),
                    "vector_store_ids": .array(parsed.vectorStoreIds.map(JSONValue.string))
                ]
                if let max = parsed.maxNumResults {
                    payload["max_num_results"] = .number(Double(max))
                }
                if let rankingOptions {
                    payload["ranking_options"] = rankingOptions
                }
                if let filters = parsed.filters {
                    payload["filters"] = filters
                }
                openAITools.append(.object(payload))

            case "openai.local_shell":
                openAITools.append(.object([
                    "type": .string("local_shell")
                ]))

            case "openai.web_search_preview":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiWebSearchPreviewArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_search_preview")
                ]
                if let size = parsed.searchContextSize {
                    payload["search_context_size"] = .string(size)
                }
                if let location = parsed.userLocation {
                    payload["user_location"] = makeUserLocationJSON(location)
                }
                openAITools.append(.object(payload))

            case "openai.web_search":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiWebSearchArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("web_search")
                ]
                if let filters = parsed.filters {
                    var filtersPayload: [String: JSONValue] = [:]
                    if let allowed = filters.allowedDomains {
                        filtersPayload["allowed_domains"] = .array(allowed.map(JSONValue.string))
                    }
                    if !filtersPayload.isEmpty {
                        payload["filters"] = .object(filtersPayload)
                    }
                }
                if let size = parsed.searchContextSize {
                    payload["search_context_size"] = .string(size)
                }
                if let location = parsed.userLocation {
                    payload["user_location"] = makeUserLocationJSON(location)
                }
                openAITools.append(.object(payload))

            case "openai.code_interpreter":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiCodeInterpreterArgsSchema)
                )
                var containerJSON: JSONValue
                if let container = parsed.container {
                    switch container {
                    case .string(let value):
                        containerJSON = .string(value)
                    case .auto(let fileIds):
                        var payload: [String: JSONValue] = [
                            "type": .string("auto")
                        ]
                        if let fileIds {
                            payload["file_ids"] = .array(fileIds.map(JSONValue.string))
                        }
                        containerJSON = .object(payload)
                    }
                } else {
                    containerJSON = .object([
                        "type": .string("auto")
                    ])
                }

                openAITools.append(.object([
                    "type": .string("code_interpreter"),
                    "container": containerJSON
                ]))

            case "openai.image_generation":
                let parsed = try await validateTypes(
                    ValidateTypesOptions(value: providerTool.args, schema: openaiImageGenerationArgsSchema)
                )
                var payload: [String: JSONValue] = [
                    "type": .string("image_generation")
                ]
                if let background = parsed.background {
                    payload["background"] = .string(background)
                }
                if let fidelity = parsed.inputFidelity {
                    payload["input_fidelity"] = .string(fidelity)
                }
                if let mask = parsed.inputImageMask {
                    var maskPayload: [String: JSONValue] = [:]
                    if let fileId = mask.fileId {
                        maskPayload["file_id"] = .string(fileId)
                    }
                    if let imageUrl = mask.imageUrl {
                        maskPayload["image_url"] = .string(imageUrl)
                    }
                    payload["input_image_mask"] = .object(maskPayload)
                }
                if let model = parsed.model {
                    payload["model"] = .string(model)
                }
                if let moderation = parsed.moderation {
                    payload["moderation"] = .string(moderation)
                }
                if let compression = parsed.outputCompression {
                    payload["output_compression"] = .number(Double(compression))
                }
                if let format = parsed.outputFormat {
                    payload["output_format"] = .string(format)
                }
                if let partial = parsed.partialImages {
                    payload["partial_images"] = .number(Double(partial))
                }
                if let quality = parsed.quality {
                    payload["quality"] = .string(quality)
                }
                if let size = parsed.size {
                    payload["size"] = .string(size)
                }
                openAITools.append(.object(payload))

            default:
                warnings.append(.unsupportedTool(tool: .providerDefined(providerTool), details: nil))
            }
        }
    }

    let finalTools = openAITools.isEmpty ? nil : openAITools
    let finalToolChoice = try mapToolChoice(toolChoice)

    return OpenAIResponsesPreparedTools(tools: finalTools, toolChoice: finalToolChoice, warnings: warnings)
}

private func makeUserLocationJSON(_ location: OpenAIWebSearchArgs.UserLocation) -> JSONValue {
    var payload: [String: JSONValue] = [
        "type": .string("approximate")
    ]
    if let country = location.country {
        payload["country"] = .string(country)
    }
    if let city = location.city {
        payload["city"] = .string(city)
    }
    if let region = location.region {
        payload["region"] = .string(region)
    }
    if let timezone = location.timezone {
        payload["timezone"] = .string(timezone)
    }
    return .object(payload)
}

private func mapToolChoice(_ choice: LanguageModelV3ToolChoice?) throws -> JSONValue? {
    guard let choice else { return nil }

    switch choice {
    case .auto:
        return .string("auto")
    case .none:
        return .string("none")
    case .required:
        return .string("required")
    case .tool(let toolName):
        if ["code_interpreter", "file_search", "image_generation", "web_search_preview", "web_search"].contains(toolName) {
            return .object(["type": .string(toolName)])
        }
        return .object([
            "type": .string("function"),
            "name": .string(toolName)
        ])
    }
}

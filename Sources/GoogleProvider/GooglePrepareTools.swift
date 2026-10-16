import AISDKProvider

struct GooglePreparedTools: Sendable {
    let tools: JSONValue?
    let toolConfig: JSONValue?
    let toolWarnings: [SharedV4Warning]
}

func prepareGoogleTools(
    tools: [LanguageModelV4Tool]?,
    toolChoice: LanguageModelV4ToolChoice?,
    modelId: GoogleModelId,
    isVertexProvider: Bool = false
) -> GooglePreparedTools {
    guard let tools, !tools.isEmpty else {
        return .init(tools: nil, toolConfig: nil, toolWarnings: [])
    }
    let capabilities = googleModelCapabilities(modelId.rawValue)
    let functions = tools.compactMap { tool -> LanguageModelV4FunctionTool? in
        if case .function(let function) = tool { return function }
        return nil
    }
    let providers = tools.compactMap { tool -> LanguageModelV4ProviderTool? in
        if case .provider(let provider) = tool { return provider }
        return nil
    }
    var warnings: [SharedV4Warning] = []
    if !functions.isEmpty && !providers.isEmpty && !capabilities.usesGemini3Features {
        warnings.append(.unsupported(feature: "combination of function and provider-defined tools", details: nil))
    }
    let declarations: JSONValue = .object(["functionDeclarations": .array(functions.map { function in
        .object([
            "name": .string(function.name),
            "description": .string(function.description ?? ""),
            "parametersJsonSchema": function.inputSchema
        ])
    })])
    var entries: [JSONValue] = []
    for tool in providers {
        let key: String
        let supported: Bool
        let details: String
        var args: [String: JSONValue] = [:]
        switch tool.id {
        case "google.google_search":
            key = "googleSearch"; supported = capabilities.supportsGemini2Tools
            details = "Google Search requires Gemini 2.0 or newer."
            args = tool.args
        case "google.enterprise_web_search":
            key = "enterpriseWebSearch"; supported = capabilities.supportsGemini2Tools
            details = "Enterprise Web Search requires Gemini 2.0 or newer."
        case "google.url_context":
            key = "urlContext"; supported = capabilities.supportsGemini2Tools
            details = "The URL context tool is not supported with other Gemini models than Gemini 2."
        case "google.code_execution":
            key = "codeExecution"; supported = capabilities.supportsGemini2Tools
            details = "The code execution tool is not supported with other Gemini models than Gemini 2."
        case "google.file_search":
            key = "fileSearch"; supported = capabilities.supportsFileSearch
            details = "The file search tool is only supported with Gemini 2.5 models and Gemini 3 models."
            args = tool.args
        case "google.vertex_rag_store":
            key = "retrieval"; supported = capabilities.supportsGemini2Tools
            details = "The RAG store tool is not supported with other Gemini models than Gemini 2."
            var store: [String: JSONValue] = ["rag_resources": .object(["rag_corpus": tool.args["ragCorpus"] ?? .null])]
            if let topK = tool.args["topK"], topK != .null { store["similarity_top_k"] = topK }
            args = ["vertex_rag_store": .object(store)]
        case "google.google_maps":
            key = "googleMaps"; supported = capabilities.supportsGemini2Tools
            details = "The Google Maps grounding tool is not supported with Gemini models other than Gemini 2 or newer."
        default:
            warnings.append(.unsupported(feature: "provider-defined tool \(tool.id)", details: nil))
            continue
        }
        if supported { entries.append(.object([key: .object(args)])) }
        else { warnings.append(.unsupported(feature: "provider-defined tool \(tool.id)", details: details)) }
    }
    let combined = !providers.isEmpty && !functions.isEmpty && capabilities.usesGemini3Features && !entries.isEmpty
    if !providers.isEmpty && !combined {
        return .init(tools: entries.isEmpty ? nil : .array(entries), toolConfig: nil, toolWarnings: warnings)
    }
    entries.append(declarations)
    let strict = functions.contains { $0.strict == true }
    var calling: [String: JSONValue] = ["mode": .string(combined || strict ? "VALIDATED" : "AUTO")]
    switch toolChoice {
    case .none?: calling["mode"] = .string("NONE")
    case .required?: calling["mode"] = .string("ANY")
    case .tool(let name)?:
        calling["mode"] = .string("ANY")
        calling["allowedFunctionNames"] = .array([.string(name)])
    default: break
    }
    var config: [String: JSONValue] = ["functionCallingConfig": .object(calling)]
    if combined && !isVertexProvider { config["includeServerSideToolInvocations"] = .bool(true) }
    return .init(
        tools: .array(entries),
        toolConfig: toolChoice != nil || strict || combined ? .object(config) : nil,
        toolWarnings: warnings
    )
}

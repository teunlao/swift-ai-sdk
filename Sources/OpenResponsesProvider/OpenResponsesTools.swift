import AISDKProvider
import AISDKProviderUtils

public struct OpenResponsesCustomToolOptions: Sendable {
    public enum Format: Sendable, Equatable {
        public enum Syntax: String, Sendable { case regex, lark }
        case text
        case grammar(syntax: Syntax, definition: String)
    }
    public var description: String?
    public var format: Format?
    public var behavior: ProviderDefinedToolFactoryOptions

    public init(description: String? = nil, format: Format? = nil, behavior: ProviderDefinedToolFactoryOptions = .init()) {
        self.description = description
        self.format = format
        self.behavior = behavior
    }
}

public struct OpenResponsesTools: Sendable {
    private let customToolId: String
    init(customToolId: String) { self.customToolId = customToolId }

    public func customTool(_ options: OpenResponsesCustomToolOptions = .init()) -> Tool {
        var behavior = options.behavior
        if let description = options.description { behavior.args["description"] = .string(description) }
        if let format = options.format {
            switch format {
            case .text: behavior.args["format"] = ["type": "text"]
            case .grammar(let syntax, let definition): behavior.args["format"] = ["type": "grammar", "syntax": .string(syntax.rawValue), "definition": .string(definition)]
            }
        }
        return createProviderDefinedToolFactory(id: customToolId, name: "custom", inputSchema: FlexibleSchema(jsonSchema(["type": "string"])))(behavior)
    }
}

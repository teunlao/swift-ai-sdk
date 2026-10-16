import Foundation
import AISDKProvider

public struct ProviderDefinedToolFactoryOptions: Sendable {
    public var execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)?
    public var outputSchema: FlexibleSchema<JSONValue>?
    public var needsApproval: NeedsApproval?
    public var toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)?
    public var onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)?
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?
    public var args: [String: JSONValue]

    public init(
        execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
        outputSchema: FlexibleSchema<JSONValue>? = nil,
        needsApproval: NeedsApproval? = nil,
        toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)? = nil,
        onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
        onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
        onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
        args: [String: JSONValue] = [:]
    ) {
        self.execute = execute
        self.outputSchema = outputSchema
        self.needsApproval = needsApproval
        self.toModelOutput = toModelOutput
        self.onInputStart = onInputStart
        self.onInputDelta = onInputDelta
        self.onInputAvailable = onInputAvailable
        self.args = args
    }
}

public struct ProviderDefinedToolFactoryWithOutputSchemaOptions: Sendable {
    public var execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)?
    public var needsApproval: NeedsApproval?
    public var toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)?
    public var onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)?
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?
    public var args: [String: JSONValue]

    public init(
        execute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
        needsApproval: NeedsApproval? = nil,
        toModelOutput: (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)? = nil,
        onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
        onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
        onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
        args: [String: JSONValue] = [:]
    ) {
        self.execute = execute
        self.needsApproval = needsApproval
        self.toModelOutput = toModelOutput
        self.onInputStart = onInputStart
        self.onInputDelta = onInputDelta
        self.onInputAvailable = onInputAvailable
        self.args = args
    }
}

public struct ProviderExecutedToolFactoryOptions: Sendable {
    public var onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)?
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?
    public var args: [String: JSONValue]

    public init(
        onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
        onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
        onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
        args: [String: JSONValue] = [:]
    ) {
        self.onInputStart = onInputStart
        self.onInputDelta = onInputDelta
        self.onInputAvailable = onInputAvailable
        self.args = args
    }
}

public typealias ProviderDefinedToolFactory = @Sendable (ProviderDefinedToolFactoryOptions) -> Tool

public typealias ProviderDefinedToolFactoryWithOutputSchema =
    @Sendable (ProviderDefinedToolFactoryWithOutputSchemaOptions) -> Tool

public typealias ProviderExecutedToolFactory = @Sendable (ProviderExecutedToolFactoryOptions) -> Tool

public func createProviderDefinedToolFactory(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>
) -> ProviderDefinedToolFactory {
    createProviderDefinedToolFactory(
        id: id,
        name: name,
        inputSchema: inputSchema,
        mapOptions: { $0 }
    )
}

public func createProviderDefinedToolFactoryWithOutputSchema(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    outputSchema: FlexibleSchema<JSONValue>
) -> ProviderDefinedToolFactoryWithOutputSchema {
    createProviderDefinedToolFactoryWithOutputSchema(
        id: id,
        name: name,
        inputSchema: inputSchema,
        outputSchema: outputSchema,
        mapOptions: { $0 }
    )
}

public func createProviderExecutedToolFactory(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    outputSchema: FlexibleSchema<JSONValue>,
    supportsDeferredResults: Bool? = nil
) -> ProviderExecutedToolFactory {
    createProviderExecutedToolFactory(
        id: id,
        name: name,
        inputSchema: inputSchema,
        outputSchema: outputSchema,
        supportsDeferredResults: supportsDeferredResults,
        mapOptions: { $0 }
    )
}

public func createProviderDefinedToolFactory<Options>(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    mapOptions: @escaping @Sendable (Options) -> ProviderDefinedToolFactoryOptions
) -> @Sendable (Options) -> Tool {
    {
        let options = mapOptions($0)
        return Tool(
            inputSchema: inputSchema,
            needsApproval: options.needsApproval,
            onInputStart: options.onInputStart,
            onInputDelta: options.onInputDelta,
            onInputAvailable: options.onInputAvailable,
            execute: options.execute,
            outputSchema: options.outputSchema,
            toModelOutput: options.toModelOutput,
            type: .provider,
            id: id,
            name: name,
            args: options.args,
            isProviderExecuted: false
        )
    }
}

public func createProviderDefinedToolFactoryWithOutputSchema<Options>(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    outputSchema: FlexibleSchema<JSONValue>,
    mapOptions: @escaping @Sendable (Options) -> ProviderDefinedToolFactoryWithOutputSchemaOptions
) -> @Sendable (Options) -> Tool {
    {
        let options = mapOptions($0)
        return Tool(
            inputSchema: inputSchema,
            needsApproval: options.needsApproval,
            onInputStart: options.onInputStart,
            onInputDelta: options.onInputDelta,
            onInputAvailable: options.onInputAvailable,
            execute: options.execute,
            outputSchema: outputSchema,
            toModelOutput: options.toModelOutput,
            type: .provider,
            id: id,
            name: name,
            args: options.args,
            isProviderExecuted: false
        )
    }
}

public func createProviderExecutedToolFactory<Options>(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    outputSchema: FlexibleSchema<JSONValue>,
    supportsDeferredResults: Bool? = nil,
    mapOptions: @escaping @Sendable (Options) -> ProviderExecutedToolFactoryOptions
) -> @Sendable (Options) -> Tool {
    {
        let options = mapOptions($0)
        return Tool(
            inputSchema: inputSchema,
            onInputStart: options.onInputStart,
            onInputDelta: options.onInputDelta,
            onInputAvailable: options.onInputAvailable,
            outputSchema: outputSchema,
            type: .provider,
            id: id,
            name: name,
            args: options.args,
            isProviderExecuted: true,
            supportsDeferredResults: supportsDeferredResults
        )
    }
}

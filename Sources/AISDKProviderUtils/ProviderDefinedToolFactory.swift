import Foundation
import AISDKProvider

/**
 Helpers for creating provider-defined tools.

 Port of `@ai-sdk/provider-utils/src/provider-defined-tool-factory.ts`.
 */

// MARK: - Common option containers

/**
 Convenience container that mirrors the upstream `ARGS & { ... }` shape.

 Provider-specific arguments are stored in `args` and forwarded to the resulting
 `Tool`. The remaining fields correspond to the shared factory options in the
 TypeScript implementation.
 */
public struct ProviderDefinedToolFactoryOptions: Sendable {
    public var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?
    public var outputSchema: FlexibleSchema<JSONValue>?
    public var needsApproval: NeedsApproval?
    public var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?
    public var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)?
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?
    public var args: [String: JSONValue]

    public init(
        execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
        outputSchema: FlexibleSchema<JSONValue>? = nil,
        needsApproval: NeedsApproval? = nil,
        toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? = nil,
        onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
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

/**
 Variant used when the output schema is defined up front by the factory creator.

 Upstream omits `outputSchema` from the options type entirely; this Swift
 adaptation mirrors that contract.
 */
public struct ProviderDefinedToolFactoryWithOutputSchemaOptions: Sendable {
    public var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?
    public var needsApproval: NeedsApproval?
    public var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?
    public var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)?
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?
    public var args: [String: JSONValue]

    public init(
        execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)? = nil,
        needsApproval: NeedsApproval? = nil,
        toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? = nil,
        onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
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

// MARK: - Factory type aliases

public typealias ProviderDefinedToolFactory = @Sendable (ProviderDefinedToolFactoryOptions) -> Tool

public typealias ProviderDefinedToolFactoryWithOutputSchema =
    @Sendable (ProviderDefinedToolFactoryWithOutputSchemaOptions) -> Tool

// MARK: - Factory creation (default options container)

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

// MARK: - Factory creation (custom option types)

/**
 Creates a provider-defined tool factory using a custom option type.

 - Parameters:
   - id: Provider tool identifier (`"<provider>.<tool-name>"`).
   - name: Human-readable name for the tool.
   - inputSchema: Input schema forwarded to the resulting `Tool`.
   - mapOptions: Closure that transforms the caller's custom options into the
     common `ProviderDefinedToolFactoryOptions` payload. This mirrors the
     TypeScript spread operator (`...args`) and allows provider-specific fields
     to be mapped into the `args` dictionary.
 */
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
            type: .providerDefined,
            id: id,
            name: name,
            args: options.args
        )
    }
}

/**
 Equivalent to `createProviderDefinedToolFactory` but for the variant where the
 output schema is predetermined by the factory creator.
 */
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
            type: .providerDefined,
            id: id,
            name: name,
            args: options.args
        )
    }
}

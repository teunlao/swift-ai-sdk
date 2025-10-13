import Foundation
import AISDKProvider

/**
 Factory helpers for creating provider-defined tools.

 Port of `@ai-sdk/provider-utils/src/provider-defined-tool-factory.ts`.

 Swift adaptation collapses the generic INPUT/OUTPUT typing to `JSONValue`
 because the existing `Tool` representation stores JSON payloads.

 Providers can mirror the upstream `...args` contract by supplying a custom
 options type that conforms to `ProviderDefinedToolFactoryOptionsConvertible`.
 The type can expose provider-specific fields at the top level and translate
 them into the underlying `args` dictionary that is forwarded to the `Tool`
 definition.
 */

/// Shared surface for provider-defined tool factory options.
public protocol ProviderDefinedToolFactoryOptionsConvertible: Sendable {
    var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)? { get }
    var outputSchema: FlexibleSchema<JSONValue>? { get }
    var needsApproval: NeedsApproval? { get }
    var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? { get }
    var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? { get }
    var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? { get }
    var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? { get }
    var args: [String: JSONValue] { get }
}

public extension ProviderDefinedToolFactoryOptionsConvertible {
    var args: [String: JSONValue] { [:] }
}

/**
 Default options implementation that uses a dictionary for provider-specific arguments.
 */
public struct ProviderDefinedToolFactoryOptions: ProviderDefinedToolFactoryOptionsConvertible {
    /// Optional execute function for the tool. When omitted the provider is expected to execute the tool.
    public var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?

    /// Optional output schema for validating tool results.
    public var outputSchema: FlexibleSchema<JSONValue>?

    /// Approval policy for the tool.
    public var needsApproval: NeedsApproval?

    /// Optional conversion function to transform the tool result into a model output.
    public var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?

    /// Callback invoked when streaming input starts.
    public var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)?

    /// Callback invoked for streaming input deltas.
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?

    /// Callback invoked when the tool input is fully available.
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?

    /// Provider-specific arguments for configuring the tool.
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

    /// Convenience accessor for individual provider-specific arguments.
    public subscript(providerArgument key: String) -> JSONValue? {
        get { args[key] }
        set { args[key] = newValue }
    }
}

/// Closure type for provider-defined tool factories using the default options container.
public typealias ProviderDefinedToolFactory = @Sendable (ProviderDefinedToolFactoryOptions) -> Tool

/// Create a provider-defined tool factory using the default options container.
public func createProviderDefinedToolFactory(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>
) -> ProviderDefinedToolFactory {
    createProviderDefinedToolFactory(
        id: id,
        name: name,
        inputSchema: inputSchema,
        optionsType: ProviderDefinedToolFactoryOptions.self
    )
}

/// Create a provider-defined tool factory that accepts a custom options type.
public func createProviderDefinedToolFactory<Options: ProviderDefinedToolFactoryOptionsConvertible>(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    optionsType _: Options.Type
) -> @Sendable (Options) -> Tool {
    { options in
        Tool(
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

/// Shared surface for provider-defined tool factory options when the output schema is predetermined.
public protocol ProviderDefinedToolFactoryWithOutputSchemaOptionsConvertible: Sendable {
    var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)? { get }
    var needsApproval: NeedsApproval? { get }
    var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)? { get }
    var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? { get }
    var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? { get }
    var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? { get }
    var args: [String: JSONValue] { get }
}

public extension ProviderDefinedToolFactoryWithOutputSchemaOptionsConvertible {
    var args: [String: JSONValue] { [:] }
}

/**
 Default options implementation for factories with a predefined output schema.
 */
public struct ProviderDefinedToolFactoryWithOutputSchemaOptions: ProviderDefinedToolFactoryWithOutputSchemaOptionsConvertible {
    /// Optional execute function for the tool.
    public var execute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?

    /// Approval policy for the tool.
    public var needsApproval: NeedsApproval?

    /// Optional conversion function to transform the tool result into a model output.
    public var toModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?

    /// Callback invoked when streaming input starts.
    public var onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)?

    /// Callback invoked for streaming input deltas.
    public var onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)?

    /// Callback invoked when the tool input is fully available.
    public var onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)?

    /// Provider-specific arguments for configuring the tool.
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

    /// Convenience accessor for individual provider-specific arguments.
    public subscript(providerArgument key: String) -> JSONValue? {
        get { args[key] }
        set { args[key] = newValue }
    }
}

/// Closure type for provider-defined tool factories with required output schema using the default options container.
public typealias ProviderDefinedToolFactoryWithOutputSchema = @Sendable (ProviderDefinedToolFactoryWithOutputSchemaOptions) -> Tool

/// Create a provider-defined tool factory with a fixed output schema using the default options container.
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
        optionsType: ProviderDefinedToolFactoryWithOutputSchemaOptions.self
    )
}

/// Create a provider-defined tool factory with a fixed output schema that accepts a custom options type.
public func createProviderDefinedToolFactoryWithOutputSchema<Options: ProviderDefinedToolFactoryWithOutputSchemaOptionsConvertible>(
    id: String,
    name: String,
    inputSchema: FlexibleSchema<JSONValue>,
    outputSchema: FlexibleSchema<JSONValue>,
    optionsType _: Options.Type
) -> @Sendable (Options) -> Tool {
    { options in
        Tool(
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

import Foundation
import AISDKProvider
import AISDKProviderUtils
import AISDKJSONSchema

/// Generic wrapper around the erased `Tool` type.
/// Mirrors the TypeScript `Tool<Input, Output>` generics so call sites get
/// strong typing while we keep compatibility with the existing runtime APIs.
public struct TypedTool<Input: Codable & Sendable, Output: Codable & Sendable>: Sendable {
    /// Underlying erased tool that flows through the rest of the SDK.
    public let tool: Tool

    /// Strongly-typed execute closure (if provided).
    public let execute: (@Sendable (Input, ToolCallOptions) async throws -> ToolExecutionResult<Output>)?

    /// Strongly-typed input schema (defaults to `.auto(Input.self)`).
    public let inputSchema: FlexibleSchema<Input>

    /// Optional strongly-typed output schema for validation.
    public let outputSchema: FlexibleSchema<Output>?

    /// Convenience accessor for the erased execute closure.
    public var erasedExecute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)? {
        tool.execute
    }

    /// Allow pass-through to APIs that expect `[Tool]`.
    public func eraseToTool() -> Tool { tool }
}

/// High-level helper that mirrors the ergonomics of the TypeScript `tool()` factory.
///
/// Callers work with strongly typed `Codable` values. The helper automatically:
/// - builds a JSON schema from the `Input` type (or uses the provided schema),
/// - validates/decodes incoming `JSONValue` into `Input`,
/// - encodes the result `Output` back into `JSONValue`, preserving streaming behavior.
public func tool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    strict: Bool? = nil,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: (@Sendable (Input, ToolCallOptions) async throws -> ToolExecutionResult<Output>)? = nil,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> TypedTool<Input, Output> {
    let resolvedInputSchema = inputSchema.resolve()
    let jsonInputSchema = FlexibleSchema<JSONValue>(
        jsonSchema { try await resolvedInputSchema.jsonSchema() }
    )

    let resolvedOutputSchema = outputSchema?.resolve()
    let jsonOutputSchema = resolvedOutputSchema.map { schema in
        FlexibleSchema<JSONValue>(jsonSchema { try await schema.jsonSchema() })
    }

    let wrappedExecute: (@Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue>)?
    if let execute = execute {
        wrappedExecute = { rawInput, options in
            let typedInput = try await decodeTypedInput(rawInput, schema: resolvedInputSchema)
            let typedResult = try await execute(typedInput, options)

            return try mapToolExecutionResult(typedResult) { output in
                if Output.self == JSONValue.self, let json = output as? JSONValue {
                    return json
                }

                return try encodeOutput(output)
            }
        }
    } else {
        wrappedExecute = nil
    }

    let wrappedToModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?
    if let toModelOutput {
        wrappedToModelOutput = { json in
            do {
                let output = try decodeTypedOutput(json, schema: resolvedOutputSchema)
                return toModelOutput(output)
            } catch {
                // DX: do not crash the process if tool output decoding fails.
                // Fall back to returning the raw JSON output to the model and surface the issue via stderr.
                fputs("tool(toModelOutput): Failed to decode tool output to typed value; falling back to raw JSON. Error: \(error)\n", stderr)
                return .json(value: json)
            }
        }
    } else {
        wrappedToModelOutput = nil
    }

    let erased = AISDKProviderUtils.tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: jsonInputSchema,
        strict: strict,
        needsApproval: needsApproval,
        onInputStart: onInputStart,
        onInputDelta: onInputDelta,
        onInputAvailable: onInputAvailable,
        execute: wrappedExecute,
        outputSchema: jsonOutputSchema,
        toModelOutput: wrappedToModelOutput
    )

    return TypedTool(
        tool: erased,
        execute: execute,
        inputSchema: inputSchema,
        outputSchema: outputSchema
    )
}


public extension TypedTool {
    /// Decode a tool call payload into the strongly typed input.
    func decodeInput(from json: JSONValue) async throws -> Input {
        try await decodeTypedInput(json, schema: inputSchema.resolve())
    }

    /// Convenience overload that decodes the input from a typed tool call.
    func decodeInput(from call: TypedToolCall) async throws -> Input {
        try await decodeInput(from: call.input)
    }

    /// Decode a tool result payload produced by the language model back into the strongly typed Output.
    /// Matches TypeScript `tool().execute` helper ergonomics where the output is already typed.
    func decodeOutput(from json: JSONValue) throws -> Output {
        try decodeTypedOutput(json, schema: outputSchema?.resolve())
    }

    /// Convenience overload that accepts a `TypedToolResult`.
    func decodeOutput(from result: TypedToolResult) throws -> Output {
        try decodeOutput(from: result.output)
    }
}


public func tool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: (@Sendable (Input, ToolCallOptions) async throws -> ToolExecutionResult<Output>)? = nil,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> TypedTool<Input, Output> {
    tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: FlexibleSchema.auto(inputType),
        outputSchema: outputSchema,
        needsApproval: needsApproval,
        onInputStart: onInputStart,
        onInputDelta: onInputDelta,
        onInputAvailable: onInputAvailable,
        execute: execute,
        toModelOutput: toModelOutput
    )
}

/// Convenience overload for simple (non-streaming) execute functions.
public func tool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    strict: Bool? = nil,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> Output,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> TypedTool<Input, Output> {
    tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: inputSchema,
        strict: strict,
        outputSchema: outputSchema,
        needsApproval: needsApproval,
        onInputStart: onInputStart,
        onInputDelta: onInputDelta,
        onInputAvailable: onInputAvailable,
        execute: { input, options in
            let value = try await execute(input, options)
            return .value(value)
        },
        toModelOutput: toModelOutput
    )
}

public func tool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    strict: Bool? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolCallOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> Output,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> TypedTool<Input, Output> {
    tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: FlexibleSchema.auto(inputType),
        strict: strict,
        outputSchema: outputSchema,
        needsApproval: needsApproval,
        onInputStart: onInputStart,
        onInputDelta: onInputDelta,
        onInputAvailable: onInputAvailable,
        execute: execute,
        toModelOutput: toModelOutput
    )
}

// MARK: - Dynamic Tool Helpers

public func dynamicTool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> ToolExecutionResult<Output>,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> Tool {
    let resolvedInputSchema = inputSchema.resolve()
    let jsonInputSchema = FlexibleSchema<JSONValue>(
        jsonSchema { try await resolvedInputSchema.jsonSchema() }
    )

    let resolvedOutputSchema = outputSchema?.resolve()
    let jsonOutputSchema = resolvedOutputSchema.map { schema in
        FlexibleSchema<JSONValue>(jsonSchema { try await schema.jsonSchema() })
    }

    let wrappedExecute: @Sendable (JSONValue, ToolCallOptions) async throws -> ToolExecutionResult<JSONValue> = { rawInput, options in
        let typedInput = try await decodeTypedInput(rawInput, schema: resolvedInputSchema)
        let typedResult = try await execute(typedInput, options)
        return try mapToolExecutionResult(typedResult) { output in
            try encodeOutput(output)
        }
    }

    let wrappedToModelOutput: (@Sendable (JSONValue) -> LanguageModelV3ToolResultOutput)?
    if let toModelOutput {
        wrappedToModelOutput = { json in
            do {
                let output = try decodeTypedOutput(json, schema: resolvedOutputSchema)
                return toModelOutput(output)
            } catch {
                // DX: do not crash the process if tool output decoding fails.
                // Fall back to returning the raw JSON output to the model and surface the issue via stderr.
                fputs("dynamicTool(toModelOutput): Failed to decode tool output to typed value; falling back to raw JSON. Error: \(error)\n", stderr)
                return .json(value: json)
            }
        }
    } else {
        wrappedToModelOutput = nil
    }

    return Tool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: jsonInputSchema,
        needsApproval: needsApproval,
        execute: wrappedExecute,
        outputSchema: jsonOutputSchema,
        toModelOutput: wrappedToModelOutput,
        type: .dynamic
    )
}

public func dynamicTool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> ToolExecutionResult<Output>,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> Tool {
    dynamicTool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: FlexibleSchema.auto(inputType),
        outputSchema: outputSchema,
        needsApproval: needsApproval,
        execute: execute,
        toModelOutput: toModelOutput
    )
}

public func dynamicTool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> Output,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> Tool {
    dynamicTool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: inputSchema,
        outputSchema: outputSchema,
        needsApproval: needsApproval,
        execute: { input, options in
            let output = try await execute(input, options)
            return .value(output)
        },
        toModelOutput: toModelOutput
    )
}

public func dynamicTool<Input: Codable & Sendable, Output: Codable & Sendable>(
    description: String? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> Output,
    toModelOutput: (@Sendable (Output) -> LanguageModelV3ToolResultOutput)? = nil
) -> Tool {
    dynamicTool(
        description: description,
        providerOptions: providerOptions,
        inputSchema: FlexibleSchema.auto(inputType),
        outputSchema: outputSchema,
        needsApproval: needsApproval,
        execute: execute,
        toModelOutput: toModelOutput
    )
}

// MARK: - Bridging Helpers

private func decodeTypedInput<Input: Codable & Sendable>(
    _ input: JSONValue,
    schema: Schema<Input>
) async throws -> Input {
    if Input.self == JSONValue.self, let casted = input as? Input {
        return casted
    }

    let foundation = try foundationObject(from: input)
    let validation = await schema.validate(foundation)

    switch validation {
    case .success(let value):
        return value
    case .failure(let error):
        throw error
    }
}

private func decodeTypedOutput<Output: Decodable & Sendable>(
    _ value: JSONValue,
    schema _: Schema<Output>?
) throws -> Output {
    if Output.self == JSONValue.self, let casted = value as? Output {
        return casted
    }

    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(Output.self, from: data)
}

private func mapToolExecutionResult<Output>(
    _ result: ToolExecutionResult<Output>,
    transform: @escaping @Sendable (Output) throws -> JSONValue
) throws -> ToolExecutionResult<JSONValue> {
    switch result {
    case .value(let output):
        return .value(try transform(output))

    case .future(let operation):
        return .future {
            let output = try await operation()
            return try transform(output)
        }

    case .stream(let stream):
        return .stream(AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await output in stream {
                        do {
                            let converted = try transform(output)
                            continuation.yield(converted)
                        } catch {
                            continuation.finish(throwing: error)
                            return
                        }
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        })
    }
}

private func encodeOutput<Output: Encodable>(_ value: Output) throws -> JSONValue {
    if let json = value as? JSONValue {
        return json
    }

    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    let object = try JSONSerialization.jsonObject(with: data)
    return try jsonValue(from: object)
}

private func foundationObject(from value: JSONValue) throws -> Any {
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    return try JSONSerialization.jsonObject(with: data)
}

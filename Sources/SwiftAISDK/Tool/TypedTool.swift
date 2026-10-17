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
    public let execute: (@Sendable (Input, ToolExecutionOptions) async throws -> ToolExecutionResult<Output>)?

    /// Strongly-typed input schema (defaults to `.auto(Input.self)`).
    public let inputSchema: FlexibleSchema<Input>

    /// Optional strongly-typed output schema for validation.
    public let outputSchema: FlexibleSchema<Output>?

    /// Convenience accessor for the erased execute closure.
    public var erasedExecute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)? {
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    metadata: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    contextSchema: FlexibleSchema<JSONValue>? = nil,
    strict: Bool? = nil,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: (@Sendable (Input, ToolExecutionOptions) async throws -> ToolExecutionResult<Output>)? = nil,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
) -> TypedTool<Input, Output> {
    let resolvedInputSchema = inputSchema.resolve()
    let jsonInputSchema = erasedInputSchema(resolvedInputSchema)

    let resolvedOutputSchema = outputSchema?.resolve()
    let jsonOutputSchema = resolvedOutputSchema.map { schema in
        FlexibleSchema<JSONValue>(jsonSchema { try await schema.jsonSchema() })
    }

    let wrappedExecute: (@Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue>)?
    if let execute = execute {
        wrappedExecute = { input, options in
            let typedInput = try decodeAcceptedInput(input, as: Input.self)
            let typedResult = try await execute(typedInput, options)

            return try mapToolExecutionResult(typedResult) { output in
                try encodeOutput(output)
            }
        }
    } else {
        wrappedExecute = nil
    }

    let wrappedToModelOutput = wrapTypedToModelOutput(
        toModelOutput,
        inputSchema: resolvedInputSchema,
        outputSchema: resolvedOutputSchema
    )

    let erased = AISDKProviderUtils.tool(
        description: description,
        providerOptions: providerOptions,
        metadata: metadata,
        inputSchema: jsonInputSchema,
        contextSchema: contextSchema,
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
    /// Decode a tool call payload — the input after the tool's schema accepted it — into the typed input.
    func decodeInput(from json: JSONValue) async throws -> Input {
        try decodeAcceptedInput(json, as: Input.self)
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: (@Sendable (Input, ToolExecutionOptions) async throws -> ToolExecutionResult<Output>)? = nil,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    strict: Bool? = nil,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: @escaping @Sendable (Input, ToolExecutionOptions) async throws -> Output,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    strict: Bool? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    onInputStart: (@Sendable (ToolExecutionOptions) async throws -> Void)? = nil,
    onInputDelta: (@Sendable (ToolCallDeltaOptions) async throws -> Void)? = nil,
    onInputAvailable: (@Sendable (ToolCallInputOptions) async throws -> Void)? = nil,
    execute: @escaping @Sendable (Input, ToolExecutionOptions) async throws -> Output,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolExecutionOptions) async throws -> ToolExecutionResult<Output>,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
) -> Tool {
    let resolvedInputSchema = inputSchema.resolve()
    let jsonInputSchema = erasedInputSchema(resolvedInputSchema)

    let resolvedOutputSchema = outputSchema?.resolve()
    let jsonOutputSchema = resolvedOutputSchema.map { schema in
        FlexibleSchema<JSONValue>(jsonSchema { try await schema.jsonSchema() })
    }

    let wrappedExecute: @Sendable (JSONValue, ToolExecutionOptions) async throws -> ToolExecutionResult<JSONValue> = { input, options in
        let typedInput = try decodeAcceptedInput(input, as: Input.self)
        let typedResult = try await execute(typedInput, options)
        return try mapToolExecutionResult(typedResult) { output in
            try encodeOutput(output)
        }
    }

    let wrappedToModelOutput = wrapTypedToModelOutput(
        toModelOutput,
        inputSchema: resolvedInputSchema,
        outputSchema: resolvedOutputSchema
    )

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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolExecutionOptions) async throws -> ToolExecutionResult<Output>,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema: FlexibleSchema<Input> = FlexibleSchema.auto(Input.self),
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolExecutionOptions) async throws -> Output,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
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
    description: ToolDescription? = nil,
    providerOptions: [String: JSONValue]? = nil,
    inputSchema inputType: Input.Type,
    outputSchema: FlexibleSchema<Output>? = nil,
    needsApproval: NeedsApproval? = nil,
    execute: @escaping @Sendable (Input, ToolExecutionOptions) async throws -> Output,
    toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)? = nil
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

/// Options passed to a typed tool's `toModelOutput`.
public struct TypedToolModelOutputOptions<Input: Sendable, Output: Sendable>: Sendable {
    /// The ID of the tool call.
    public let toolCallId: String

    /// The input of the tool call.
    public let input: Input

    /// The output of the tool call.
    public let output: Output
}

// MARK: - Bridging Helpers

private func wrapTypedToModelOutput<Input: Codable & Sendable, Output: Codable & Sendable>(
    _ toModelOutput: (@Sendable (TypedToolModelOutputOptions<Input, Output>) async throws -> ToolResultOutput)?,
    inputSchema: Schema<Input>,
    outputSchema: Schema<Output>?
) -> (@Sendable (ToolModelOutputOptions) async throws -> ToolResultOutput)? {
    guard let toModelOutput else { return nil }
    return { options in
        let input = try decodeAcceptedInput(options.input, as: Input.self)
        let output = try decodeTypedOutput(options.output, schema: outputSchema)
        return try await toModelOutput(
            TypedToolModelOutputOptions(toolCallId: options.toolCallId, input: input, output: output)
        )
    }
}

/// The erased input schema runs the typed schema when the call is parsed, so an invalid input
/// reaches tool-call repair and approval, callbacks and `execute` all see the accepted input.
private func erasedInputSchema<Input: Codable & Sendable>(
    _ schema: Schema<Input>
) -> FlexibleSchema<JSONValue> {
    FlexibleSchema(Schema(
        jsonSchemaResolver: { try await schema.jsonSchema() },
        validator: { value in
            switch await schema.validate(value) {
            case .success(let input):
                return .success(value: try encodeAcceptedInput(input))
            case .failure(let error):
                return .failure(error: error)
            }
        }
    ))
}

private func encodeAcceptedInput<Input: Encodable>(_ input: Input) throws -> JSONValue {
    if let json = input as? JSONValue {
        return json
    }
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .custom { date, encoder in
        var container = encoder.singleValueContainer()
        try container.encode(acceptedInputDateFormatter().string(from: date))
    }
    return try JSONDecoder().decode(JSONValue.self, from: encoder.encode(input))
}

/// Decodes an input `encodeAcceptedInput` produced, without running the schema again.
private func decodeAcceptedInput<Input: Decodable>(_ json: JSONValue, as _: Input.Type) throws -> Input {
    if let input = json as? Input {
        return input
    }
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
        let container = try decoder.singleValueContainer()
        let text = try container.decode(String.self)
        let formatter = acceptedInputDateFormatter()
        if let date = formatter.date(from: text) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) {
            return date
        }
        throw DecodingError.dataCorruptedError(
            in: container,
            debugDescription: "Expected date string to be ISO8601-formatted."
        )
    }
    return try decoder.decode(Input.self, from: JSONEncoder().encode(json))
}

private func acceptedInputDateFormatter() -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
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

    return try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
}

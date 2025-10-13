/**
 Async helper for normalizing tool execution streams.

 Port of `@ai-sdk/provider-utils/src/types/execute-tool.ts`.
 */
import Foundation
import AISDKProvider

/**
 Output from tool execution, indicating whether it's preliminary or final.

 Port of `@ai-sdk/provider-utils/src/types/execute-tool.ts` - output types.

 TypeScript upstream yields `{ type: 'preliminary' | 'final'; output: OUTPUT }`.
 Swift adaptation uses enum with associated values:
 - `.preliminary(Output)`: Intermediate streaming result
 - `.final(Output)`: Final result (last stream value or non-streaming result)
 */
public enum ToolExecutionOutput<Output: Sendable>: Sendable {
    /// Intermediate streaming result (preliminary).
    case preliminary(Output)

    /// Final результат (может отсутствовать для пустого стрима).
    case final(Output?)

    /// Возвращает значение результата (для финального события может быть nil).
    public var output: Output? {
        switch self {
        case .preliminary(let output):
            return output
        case .final(let output):
            return output
        }
    }

    /// Check if this is a preliminary result.
    public var isPreliminary: Bool {
        if case .preliminary = self { return true }
        return false
    }

    /// Check if this is a final result.
    public var isFinal: Bool {
        if case .final = self { return true }
        return false
    }
}

/**
 Execute a tool and yield preliminary and final results.

 Port of `@ai-sdk/provider-utils/src/types/execute-tool.ts` - `executeTool()` function.

 This function normalizes tool execution results:
 - For streaming results (`.stream`): yields preliminary outputs for each stream value,
   then yields final output with the last value
 - For non-streaming results (`.value`, `.future`): yields only final output

 ## Upstream Behavior

 TypeScript:
 ```typescript
 export async function* executeTool<INPUT, OUTPUT>({
   execute,
   input,
   options,
 }): AsyncGenerator<{ type: 'preliminary' | 'final'; output: OUTPUT }> {
   const result = execute(input, options);

   if (isAsyncIterable(result)) {
     let lastOutput: OUTPUT | undefined;
     for await (const output of result) {
       lastOutput = output;
       yield { type: 'preliminary', output };
     }
     yield { type: 'final', output: lastOutput! };
   } else {
     yield { type: 'final', output: await result };
   }
 }
 ```

 Swift:
 ```swift
 let stream = executeTool(
     execute: tool.execute!,
     input: input,
     options: options
 )

 for try await part in stream {
     switch part {
     case .preliminary(let output):
         print("Intermediate: \(output)")
     case .final(let output):
         print("Final: \(output)")
     }
 }
 ```

 - Parameters:
   - execute: The tool execution function that returns `ToolExecutionResult`
   - input: The input to pass to the tool
   - options: Tool call options (ID, messages, abort signal, etc.)

 - Returns: An `AsyncThrowingStream` yielding preliminary and final outputs

 - Throws: Propagates errors from tool execution
 */
public func executeTool<Input: Sendable, Output: Sendable>(
    execute: @escaping @Sendable (Input, ToolCallOptions) async throws -> ToolExecutionResult<Output>,
    input: Input,
    options: ToolCallOptions
) -> AsyncThrowingStream<ToolExecutionOutput<Output>, Error> {
    return AsyncThrowingStream { continuation in
        let task = Task {
            do {
                let result = try await execute(input, options)

                if result.isStreaming {
                    // Streaming result: yield preliminary outputs, then final
                    let stream = result.asAsyncStream()
                    var lastOutput: Output?

                    for try await output in stream {
                        lastOutput = output
                        continuation.yield(.preliminary(output))
                    }

                    continuation.yield(.final(lastOutput))
                } else {
                    // Non-streaming result: yield only final
                    let value = try await result.resolve()
                    continuation.yield(.final(value))
                }

                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}

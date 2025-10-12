/**
 Error handler callback type.

 Port of `@ai-sdk/ai/src/util/error-handler.ts`.

 A callback function that receives and handles errors.
 */
public typealias ErrorHandler = @Sendable (Error) -> Void

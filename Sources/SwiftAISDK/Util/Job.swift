/**
 Type alias for asynchronous job execution.

 Port of `@ai-sdk/ai/src/util/job.ts`.

 Represents a unit of work that returns a Promise in TypeScript.
 In Swift, this is represented as an async throwing function.
 */

/// A job that can be executed asynchronously.
///
/// Jobs are used with `SerialJobExecutor` to execute work serially.
/// The job returns `Void` and can throw errors.
public typealias Job = @Sendable () async throws -> Void

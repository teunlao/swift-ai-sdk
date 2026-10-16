import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Condition evaluated after each step with tool results; the loop stops when it returns `true`.

 Port of `@ai-sdk/ai/src/generate-text/stop-condition.ts`.
 */
public typealias StopCondition = @Sendable (_ steps: [StepResult]) async throws -> Bool

/// Stops when the number of steps equals `stepCount`.
public func isStepCount(_ stepCount: Int) -> StopCondition {
    { steps in steps.count == stepCount }
}

@available(*, deprecated, renamed: "isStepCount")
public func stepCountIs(_ stepCount: Int) -> StopCondition {
    isStepCount(stepCount)
}

/// Never stops the loop; the loop ends when the model stops calling tools.
public func isLoopFinished() -> StopCondition {
    { _ in false }
}

/// Stops when the last step called one of the given tools.
public func hasToolCall(_ toolNames: String...) -> StopCondition {
    { steps in
        steps.last?.toolCalls.contains { toolNames.contains($0.toolName) } ?? false
    }
}

/// Whether any stop condition is met. The conditions run concurrently.
public func isStopConditionMet(
    stopConditions: [StopCondition],
    steps: [StepResult]
) async throws -> Bool {
    try await withThrowingTaskGroup(of: Bool.self) { group in
        for condition in stopConditions {
            group.addTask { try await condition(steps) }
        }
        var met = false
        for try await result in group where result {
            met = true
        }
        return met
    }
}

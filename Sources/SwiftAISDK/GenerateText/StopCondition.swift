/**
 Stop conditions for multi-step generation.

 Port of `@ai-sdk/ai/src/generate-text/stop-condition.ts`.

 Provides functions to check when multi-step generation should stop:
 - `stepCountIs(n)`: Stop when step count reaches n
 - `hasToolCall(name)`: Stop when specific tool is called
 - `isStopConditionMet()`: Check if any stop condition is satisfied
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Stop condition function type
/// - Parameter steps: Array of step results
/// - Returns: true if generation should stop, false otherwise
public typealias StopCondition = @Sendable (_ steps: [StepResult]) async -> Bool

/// Creates a stop condition that stops after a specific number of steps
/// - Parameter stepCount: Number of steps after which to stop
/// - Returns: Stop condition function
public func stepCountIs(_ stepCount: Int) -> StopCondition {
    return { steps in
        return steps.count == stepCount
    }
}

/// Creates a stop condition that stops when a specific tool is called
/// - Parameter toolName: Name of the tool to check for
/// - Returns: Stop condition function
public func hasToolCall(_ toolName: String) -> StopCondition {
    return { steps in
        guard let lastStep = steps.last else {
            return false
        }

        return lastStep.toolCalls.contains { toolCall in
            toolCall.toolName == toolName
        }
    }
}

/// Check if any stop condition is met
/// - Parameters:
///   - stopConditions: Array of stop conditions to check
///   - steps: Array of step results to evaluate
/// - Returns: true if any stop condition is satisfied, false otherwise
public func isStopConditionMet(
    stopConditions: [StopCondition],
    steps: [StepResult]
) async -> Bool {
    let results = await withTaskGroup(of: Bool.self) { group in
        for condition in stopConditions {
            group.addTask {
                await condition(steps)
            }
        }

        var results: [Bool] = []
        for await result in group {
            results.append(result)
        }
        return results
    }

    return results.contains(true)
}

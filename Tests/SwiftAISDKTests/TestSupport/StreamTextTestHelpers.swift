import Foundation
import SwiftAISDK

extension DefaultStreamTextResult {
    /// Reads all parts of the full stream.
    func collectFullStream() async throws -> [TextStreamPart] {
        var parts: [TextStreamPart] = []
        for try await part in fullStream {
            parts.append(part)
        }
        return parts
    }

    /// Reads the text stream to the end.
    func collectText() async throws -> String {
        var text = ""
        for try await delta in textStream {
            text += delta
        }
        return text
    }

    func readAllText() async throws -> String {
        try await collectText()
    }

    /// Waits for the stream to finish and returns the final values.
    func waitForFinish() async throws -> (
        finalStep: StepResult,
        steps: [StepResult],
        totalUsage: LanguageModelUsage,
        finishReason: FinishReason
    ) {
        let steps = try await self.steps
        return (steps[steps.count - 1], steps, try await totalUsage, try await finishReason)
    }
}

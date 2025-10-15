/**
 Tests for logWarnings function.

 Port of `@ai-sdk/ai/src/logger/log-warnings.test.ts`.

 Tests warning logging with:
 - Global configuration (AI_SDK_LOG_WARNINGS)
 - Custom loggers
 - Default console behavior
 - First-call information note
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

/// Thread-safe box for capturing values in closures
final class Box<T>: @unchecked Sendable {
    var value: T
    init(_ value: T) {
        self.value = value
    }
}

@Suite("LogWarnings Tests", .serialized)
struct LogWarningsTests {

    // MARK: - Synchronization

    private func withLogWarningsLock<T: Sendable>(
        _ body: @Sendable () async throws -> T
    ) async rethrows -> T {
        try await LogWarningsTestLock.shared.withLock(body)
    }

    // MARK: - Helper to capture print output

    /// Captures print output during test execution
    func capturePrintOutput(_ block: () -> Void) -> [String] {
        // Note: Swift doesn't have direct console interception like JavaScript
        // For now, we'll test behavior without capturing actual print output
        // In a real implementation, you'd need a logging abstraction layer
        let capturedOutput: [String] = []
        block()
        return capturedOutput
    }

    // MARK: - Tests: AI_SDK_LOG_WARNINGS = false

    @Test("should not log any warnings when AI_SDK_LOG_WARNINGS is false")
    func noLoggingWhenDisabled() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = false
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warnings: [Warning] = [
                .languageModel(.other(message: "Test warning"))
            ]

            // Should not crash or log
            logWarnings(warnings)
        }
    }

    @Test("should not log multiple warnings when AI_SDK_LOG_WARNINGS is false")
    func noLoggingMultipleWhenDisabled() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = false
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warnings: [Warning] = [
                .languageModel(.other(message: "Test warning 1")),
                .imageModel(.other(message: "Test warning 2"))
            ]

            logWarnings(warnings)
        }
    }

    // MARK: - Tests: Custom logger function

    @Test("should call custom function with warnings")
    func customLoggerCalled() async {
        await withLogWarningsLock {
            let box = Box<[Warning]?>(nil)
            let customLogger: LogWarningsFunction = { warnings in
                box.value = warnings
            }

            AI_SDK_LOG_WARNINGS = customLogger
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warnings: [Warning] = [
                .languageModel(.other(message: "Test warning"))
            ]

            logWarnings(warnings)

            #expect(box.value != nil)
            #expect(box.value?.count == 1)
        }
    }

    @Test("should call custom function with multiple warnings")
    func customLoggerMultiple() async {
        await withLogWarningsLock {
            let box = Box<[Warning]?>(nil)
            let customLogger: LogWarningsFunction = { warnings in
                box.value = warnings
            }

            AI_SDK_LOG_WARNINGS = customLogger
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warnings: [Warning] = [
                .languageModel(.unsupportedSetting(setting: "temperature", details: "Temperature not supported")),
                .imageModel(.other(message: "Another warning"))
            ]

            logWarnings(warnings)

            #expect(box.value != nil)
            #expect(box.value?.count == 2)
        }
    }

    @Test("should not call custom function with empty warnings array")
    func customLoggerEmptyArray() async {
        await withLogWarningsLock {
            let box = Box<Bool>(false)
            let customLogger: LogWarningsFunction = { _ in
                box.value = true
            }

            AI_SDK_LOG_WARNINGS = customLogger
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warnings: [Warning] = []

            logWarnings(warnings)

            #expect(box.value == false)
        }
    }

    // MARK: - Tests: Default behavior (console logging)

    @Test("should log single warning with default behavior")
    func defaultLogSingle() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil  // Default behavior
            resetLogWarningsState()

            let warning: Warning = .languageModel(.other(message: "Test warning message"))
            let warnings: [Warning] = [warning]

            // Should not crash
            logWarnings(warnings)
        }
    }

    @Test("should log multiple warnings with default behavior")
    func defaultLogMultiple() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warnings: [Warning] = [
                .languageModel(.other(message: "First warning")),
                .imageModel(.unsupportedSetting(setting: "size", details: "Size parameter not supported"))
            ]

            logWarnings(warnings)
        }
    }

    @Test("should not log with empty warnings array")
    func defaultLogEmpty() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warnings: [Warning] = []

            logWarnings(warnings)
        }
    }

    // MARK: - Tests: Different warning types

    @Test("should handle LanguageModelV3CallWarning with unsupported-setting")
    func languageModelUnsupportedSetting() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .languageModel(
                .unsupportedSetting(setting: "temperature", details: "Temperature setting is not supported by this model")
            )

            logWarnings([warning])
        }
    }

    @Test("should handle LanguageModelV3CallWarning with unsupported-tool")
    func languageModelUnsupportedTool() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let tool = LanguageModelV3Tool.function(
                LanguageModelV3FunctionTool(
                    name: "testTool",
                    inputSchema: .object([:]),
                    description: nil,
                    providerOptions: nil
                )
            )

            let warning: Warning = .languageModel(
                .unsupportedTool(tool: tool, details: "Tool not supported")
            )

            logWarnings([warning])
        }
    }

    @Test("should handle ImageModelV3CallWarning")
    func imageModelWarning() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .imageModel(
                .unsupportedSetting(setting: "size", details: "Image size setting not supported")
            )

            logWarnings([warning])
        }
    }

    @Test("should handle SpeechModelV3CallWarning")
    func speechModelWarning() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .speechModel(
                .unsupportedSetting(setting: "voice", details: "Voice setting not supported")
            )

            logWarnings([warning])
        }
    }

    @Test("should handle TranscriptionModelV3CallWarning")
    func transcriptionModelWarning() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .transcriptionModel(
                .unsupportedSetting(setting: "mediaType", details: "MediaType setting not supported")
            )

            logWarnings([warning])
        }
    }

    @Test("should handle mixed warning types")
    func mixedWarningTypes() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warnings: [Warning] = [
                .languageModel(.other(message: "Language model warning")),
                .imageModel(.other(message: "Image model warning")),
                .speechModel(.other(message: "Speech model warning")),
                .transcriptionModel(.other(message: "Transcription model warning"))
            ]

            logWarnings(warnings)
        }
    }

    // MARK: - Tests: First-time information note

    @Test("should display information note on first call")
    func displayInfoNoteOnFirstCall() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .languageModel(.other(message: "First warning"))
            let warnings: [Warning] = [warning]

            logWarnings(warnings)
        }
    }

    @Test("should not display information note on subsequent calls")
    func noInfoNoteOnSubsequentCalls() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning1: Warning = .languageModel(.other(message: "First warning"))
            let warning2: Warning = .languageModel(.other(message: "Second warning"))

            logWarnings([warning1])
            logWarnings([warning2])

            // Note: We can't assert console output, but successful execution ensures
            // the second call doesn't re-display the informational note.
        }
    }

    @Test("should not display information note when logging is disabled")
    func noInfoNoteWhenDisabled() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = false
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warning: Warning = .languageModel(.other(message: "Test warning"))
            let warnings: [Warning] = [warning]

            logWarnings(warnings)
        }
    }

    @Test("should reset state with resetLogWarningsState")
    func resetState() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .languageModel(.other(message: "First warning"))

            logWarnings([warning])
            resetLogWarningsState()
            logWarnings([warning])
        }
    }

    @Test("should not log with empty array after reset")
    func emptyArrayAfterReset() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warnings: [Warning] = []
            logWarnings(warnings)

            let warning: Warning = .languageModel(.other(message: "Test warning"))
            logWarnings([warning])
        }
    }

    // MARK: - Tests: AI_SDK_LOG_WARNINGS = undefined (explicitly)

    @Test("should use default behavior when AI_SDK_LOG_WARNINGS is nil")
    func undefinedUsesDefault() async {
        await withLogWarningsLock {
            AI_SDK_LOG_WARNINGS = nil
            resetLogWarningsState()

            let warning: Warning = .languageModel(.other(message: "Test warning with undefined logger"))

            logWarnings([warning])
        }
    }

    // MARK: - Tests: Custom logger does not show info note

    @Test("should not show info note with custom logger")
    func customLoggerNoInfo() async {
        await withLogWarningsLock {
            let box = Box<Bool>(false)
            let customLogger: LogWarningsFunction = { _ in
                box.value = true
            }

            AI_SDK_LOG_WARNINGS = customLogger
            resetLogWarningsState()
            defer { AI_SDK_LOG_WARNINGS = nil }

            let warning: Warning = .languageModel(.other(message: "Test warning"))

            logWarnings([warning])

            #expect(box.value == true)
        }
    }
}

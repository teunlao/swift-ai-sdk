import Foundation
import Testing
@testable import SwiftAISDK

/**
 Tests for PrepareCallSettings

 Port of `@ai-sdk/ai/src/prompt/prepare-call-settings.test.ts`.
 */

@Suite("prepareCallSettings")
struct PrepareCallSettingsTests {

    // MARK: - Valid Inputs

    @Test("should not throw an error for valid settings")
    func validSettings() throws {
        let settings = try prepareCallSettings(
            maxOutputTokens: 100,
            temperature: 0.7,
            topP: 0.9,
            topK: 50,
            presencePenalty: 0.5,
            frequencyPenalty: 0.3,
            seed: 42
        )

        #expect(settings.maxOutputTokens == 100)
        #expect(settings.temperature == 0.7)
        #expect(settings.topP == 0.9)
        #expect(settings.topK == 50)
        #expect(settings.presencePenalty == 0.5)
        #expect(settings.frequencyPenalty == 0.3)
        #expect(settings.seed == 42)
        #expect(settings.stopSequences == nil)
    }

    @Test("should allow nil values for optional settings")
    func nilValues() throws {
        let settings = try prepareCallSettings(
            maxOutputTokens: nil,
            temperature: nil,
            topP: nil,
            topK: nil,
            presencePenalty: nil,
            frequencyPenalty: nil,
            seed: nil
        )

        #expect(settings.maxOutputTokens == nil)
        #expect(settings.temperature == nil)
        #expect(settings.topP == nil)
        #expect(settings.topK == nil)
        #expect(settings.presencePenalty == nil)
        #expect(settings.frequencyPenalty == nil)
        #expect(settings.seed == nil)
        #expect(settings.stopSequences == nil)
    }

    // MARK: - Invalid Inputs

    @Test("should throw InvalidArgumentError if maxOutputTokens is less than 1")
    func maxOutputTokensTooSmall() {
        #expect(throws: InvalidArgumentError.self) {
            try prepareCallSettings(maxOutputTokens: 0)
        }

        do {
            _ = try prepareCallSettings(maxOutputTokens: 0)
            Issue.record("Expected InvalidArgumentError to be thrown")
        } catch let error as InvalidArgumentError {
            #expect(error.parameter == "maxOutputTokens")
            #expect(error.value == .number(0))
            #expect(error.message == "Invalid argument for parameter maxOutputTokens: maxOutputTokens must be >= 1")
        } catch {
            Issue.record("Expected InvalidArgumentError, got \(type(of: error))")
        }
    }

    @Test("should throw InvalidArgumentError if maxOutputTokens is negative")
    func maxOutputTokensNegative() {
        #expect(throws: InvalidArgumentError.self) {
            try prepareCallSettings(maxOutputTokens: -5)
        }

        do {
            _ = try prepareCallSettings(maxOutputTokens: -5)
            Issue.record("Expected InvalidArgumentError to be thrown")
        } catch let error as InvalidArgumentError {
            #expect(error.parameter == "maxOutputTokens")
            #expect(error.value == .number(-5))
            #expect(error.message == "Invalid argument for parameter maxOutputTokens: maxOutputTokens must be >= 1")
        } catch {
            Issue.record("Expected InvalidArgumentError, got \(type(of: error))")
        }
    }

    // MARK: - Return Value Tests

    @Test("should return a new object with limited values")
    func returnsLimitedValues() throws {
        // In TypeScript, you can pass extra fields and they're ignored
        // In Swift, the type system prevents this at compile time
        // So we just verify that the function returns the correct fields
        let settings = try prepareCallSettings(
            maxOutputTokens: 100,
            temperature: 0.7
        )

        // Verify all fields are present
        #expect(settings.maxOutputTokens == 100)
        #expect(settings.temperature == 0.7)
        #expect(settings.topP == nil)
        #expect(settings.topK == nil)
        #expect(settings.presencePenalty == nil)
        #expect(settings.frequencyPenalty == nil)
        #expect(settings.stopSequences == nil)
        #expect(settings.seed == nil)
    }

    @Test("should handle stopSequences correctly")
    func stopSequences() throws {
        let sequences = ["STOP", "END", "DONE"]
        let settings = try prepareCallSettings(
            maxOutputTokens: 100,
            stopSequences: sequences
        )

        #expect(settings.stopSequences == sequences)
    }

    // MARK: - Note on Type Validation Tests
    //
    // TypeScript tests include validation for wrong types (e.g., passing string instead of number).
    // Swift's type system makes these tests impossible/unnecessary:
    // - Cannot pass String to a Double parameter (compile error)
    // - Cannot pass Double to an Int parameter (compile error)
    // - This is a Swift adaptation that provides *stronger* guarantees than runtime checks
}

/**
 Tests for selectTelemetryAttributes function.

 Port of `@ai-sdk/ai/src/telemetry/select-temetry-attributes.test.ts`.

 Tests attribute selection based on telemetry configuration:
 - Disabled telemetry returns empty
 - Input/output filtering
 - Async attribute resolution
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("SelectTelemetryAttributes Tests")
struct SelectTelemetryAttributesTests {

    @Test("should return an empty object when telemetry is disabled")
    func returnEmptyWhenDisabled() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: false),
            attributes: ["key": .value(.string("value"))]
        )
        #expect(result.isEmpty)
    }

    @Test("should return an empty object when telemetry enablement is undefined")
    func returnEmptyWhenUndefined() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: nil),
            attributes: ["key": .value(.string("value"))]
        )
        #expect(result.isEmpty)
    }

    @Test("should return attributes with simple values")
    func returnSimpleAttributes() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true),
            attributes: [
                "string": .value(.string("value")),
                "number": .value(.int(42)),
                "boolean": .value(.bool(true))
            ]
        )

        #expect(result["string"] == .string("value"))
        #expect(result["number"] == .int(42))
        #expect(result["boolean"] == .bool(true))
    }

    @Test("should handle input functions when recordInputs is true")
    func handleInputWhenEnabled() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true, recordInputs: true),
            attributes: [
                "input": .input({ .string("input value") }),
                "other": .value(.string("other value"))
            ]
        )

        #expect(result["input"] == .string("input value"))
        #expect(result["other"] == .string("other value"))
    }

    @Test("should not include input functions when recordInputs is false")
    func excludeInputWhenDisabled() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true, recordInputs: false),
            attributes: [
                "input": .input({ .string("input value") }),
                "other": .value(.string("other value"))
            ]
        )

        #expect(result["input"] == nil)
        #expect(result["other"] == .string("other value"))
    }

    @Test("should handle output functions when recordOutputs is true")
    func handleOutputWhenEnabled() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true, recordOutputs: true),
            attributes: [
                "output": .output({ .string("output value") }),
                "other": .value(.string("other value"))
            ]
        )

        #expect(result["output"] == .string("output value"))
        #expect(result["other"] == .string("other value"))
    }

    @Test("should not include output functions when recordOutputs is false")
    func excludeOutputWhenDisabled() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true, recordOutputs: false),
            attributes: [
                "output": .output({ .string("output value") }),
                "other": .value(.string("other value"))
            ]
        )

        #expect(result["output"] == nil)
        #expect(result["other"] == .string("other value"))
    }

    @Test("should ignore undefined values")
    func ignoreUndefinedValues() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true),
            attributes: [
                "defined": .value(.string("value")),
                "undefined": nil
            ]
        )

        #expect(result["defined"] == .string("value"))
        #expect(result["undefined"] == nil)
    }

    @Test("should ignore input and output functions that return undefined")
    func ignoreNilReturns() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true),
            attributes: [
                "input": .input({ nil }),
                "output": .output({ nil }),
                "other": .value(.string("value"))
            ]
        )

        #expect(result["input"] == nil)
        #expect(result["output"] == nil)
        #expect(result["other"] == .string("value"))
    }

    @Test("should handle mixed attribute types correctly")
    func handleMixedTypes() async throws {
        let result = try await selectTelemetryAttributes(
            telemetry: TelemetrySettings(isEnabled: true),
            attributes: [
                "simple": .value(.string("value")),
                "input": .input({ .string("input value") }),
                "output": .output({ .string("output value") }),
                "undefined": nil,
                "input_nil": .input({ nil })
            ]
        )

        #expect(result["simple"] == .string("value"))
        #expect(result["input"] == .string("input value"))
        #expect(result["output"] == .string("output value"))
        #expect(result["undefined"] == nil)
        #expect(result["input_nil"] == nil)
    }
}

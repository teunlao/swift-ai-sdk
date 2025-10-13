import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils

/**
 Tests for Load Settings utilities.
 Port of behavior from load-setting.ts, load-optional-setting.ts, load-api-key.ts
 */
struct LoadSettingsTests {
    // MARK: - LoadSetting

    @Test("loadSetting returns provided value")
    func testLoadSettingWithValue() throws {
        let result = try loadSetting(
            settingValue: "test-value",
            environmentVariableName: "TEST_VAR",
            settingName: "testSetting",
            description: "Test"
        )
        #expect(result == "test-value")
    }

    @Test("loadSetting throws when value missing")
    func testLoadSettingMissing() {
        #expect(throws: LoadSettingError.self) {
            _ = try loadSetting(
                settingValue: nil,
                environmentVariableName: "NONEXISTENT_VAR_12345",
                settingName: "testSetting",
                description: "Test"
            )
        }
    }

    // MARK: - LoadOptionalSetting

    @Test("loadOptionalSetting returns provided value")
    func testLoadOptionalSettingWithValue() {
        let result = loadOptionalSetting(
            settingValue: "test-value",
            environmentVariableName: "TEST_VAR"
        )
        #expect(result == "test-value")
    }

    @Test("loadOptionalSetting returns nil when missing")
    func testLoadOptionalSettingMissing() {
        let result = loadOptionalSetting(
            settingValue: nil,
            environmentVariableName: "NONEXISTENT_VAR_12345"
        )
        #expect(result == nil)
    }

    // MARK: - LoadAPIKey

    @Test("loadAPIKey returns provided value")
    func testLoadAPIKeyWithValue() throws {
        let result = try loadAPIKey(
            apiKey: "test-key",
            environmentVariableName: "TEST_API_KEY",
            description: "Test"
        )
        #expect(result == "test-key")
    }

    @Test("loadAPIKey throws when missing")
    func testLoadAPIKeyMissing() {
        #expect(throws: LoadAPIKeyError.self) {
            _ = try loadAPIKey(
                apiKey: nil,
                environmentVariableName: "NONEXISTENT_API_KEY_12345",
                description: "Test"
            )
        }
    }
}

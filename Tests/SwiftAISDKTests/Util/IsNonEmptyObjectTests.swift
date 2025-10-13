/**
 Tests for isNonEmptyObject function.

 Port of `@ai-sdk/ai/src/util/is-non-empty-object.ts`.
 Note: No upstream tests exist, so we create basic coverage tests.
 */

import Testing
import Foundation
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

@Suite("IsNonEmptyObject Tests")
struct IsNonEmptyObjectTests {

    @Test("returns false for nil")
    func returnsFalseForNil() throws {
        let result = isNonEmptyObject(nil)
        #expect(result == false)
    }

    @Test("returns false for empty object")
    func returnsFalseForEmptyObject() throws {
        let obj: [String: Any] = [:]
        let result = isNonEmptyObject(obj)
        #expect(result == false)
    }

    @Test("returns true for non-empty object")
    func returnsTrueForNonEmptyObject() throws {
        let obj: [String: Any] = ["a": 1]
        let result = isNonEmptyObject(obj)
        #expect(result == true)
    }

    @Test("returns true for object with multiple keys")
    func returnsTrueForObjectWithMultipleKeys() throws {
        let obj: [String: Any] = ["a": 1, "b": 2, "c": 3]
        let result = isNonEmptyObject(obj)
        #expect(result == true)
    }
}

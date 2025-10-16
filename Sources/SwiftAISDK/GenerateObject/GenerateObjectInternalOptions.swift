import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Internal configuration knobs for `generateObject` and `streamObject`.

 Mirrors `_internal` options from upstream TypeScript implementation.
 */
public struct GenerateObjectInternalOptions: Sendable {
    public var generateId: IDGenerator
    public var currentDate: @Sendable () -> Date
    public var now: @Sendable () -> TimeInterval

    public init(
        generateId: IDGenerator? = nil,
        currentDate: @escaping @Sendable () -> Date = Date.init,
        now: @escaping @Sendable () -> TimeInterval = { Date().timeIntervalSince1970 * 1000 }
    ) {
        if let generateId {
            self.generateId = generateId
        } else {
            self.generateId = try! createIDGenerator(prefix: "aiobj", size: 24)
        }
        self.currentDate = currentDate
        self.now = now
    }
}

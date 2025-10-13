/**
 Helper function for creating mock value sequences.

 Port of `@ai-sdk/ai/src/test/mock-values.ts`.

 Returns a closure that yields values from the provided array sequentially,
 repeating the last value once the array is exhausted.
 */

import Foundation
import AISDKProvider
import AISDKProviderUtils

/// Creates a function that returns values from an array sequentially.
///
/// After all values are consumed, the last value is repeated indefinitely.
///
/// Example:
/// ```swift
/// let mockDates = mockValues(
///     Date(timeIntervalSince1970: 1000),
///     Date(timeIntervalSince1970: 2000),
///     Date(timeIntervalSince1970: 3000)
/// )
/// mockDates() // 1000
/// mockDates() // 2000
/// mockDates() // 3000
/// mockDates() // 3000 (repeats last)
/// mockDates() // 3000 (repeats last)
/// ```
public func mockValues<T>(_ values: T...) -> () -> T {
    var counter = 0
    return {
        defer { counter += 1 }
        let index = min(counter, values.count - 1)
        return values[index]
    }
}

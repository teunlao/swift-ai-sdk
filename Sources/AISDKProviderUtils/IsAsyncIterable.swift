import Foundation

/**
 Checks if a value conforms to AsyncSequence protocol.

 Port of `@ai-sdk/provider-utils/src/is-async-iterable.ts`.

 In Swift, this is equivalent to checking if a type conforms to `AsyncSequence`.
 Since Swift uses static typing, this function checks at runtime using `is` operator.

 - Parameter value: The value to check
 - Returns: `true` if the value conforms to AsyncSequence protocol

 ## Example
 ```swift
 let stream = AsyncStream<Int> { continuation in
     continuation.yield(1)
     continuation.finish()
 }
 isAsyncIterable(stream)  // true

 let array = [1, 2, 3]
 isAsyncIterable(array)   // false (not async)
 ```
 */
public func isAsyncIterable(_ value: Any) -> Bool {
    return value is any AsyncSequence
}

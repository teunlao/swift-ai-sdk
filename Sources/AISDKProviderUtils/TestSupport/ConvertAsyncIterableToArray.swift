import Foundation

/**
 Collects all elements produced by an async sequence into an array.

 Port of `@ai-sdk/provider-utils/src/test/convert-async-iterable-to-array.ts`.
 */
public func convertAsyncIterableToArray<Sequence: AsyncSequence>(
    _ sequence: Sequence
) async rethrows -> [Sequence.Element] {
    var result: [Sequence.Element] = []
    for try await item in sequence {
        result.append(item)
    }
    return result
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Splits an array into chunks of a specified size.

 Port of `@ai-sdk/ai/src/util/split-array.ts`.

 The last chunk may contain fewer elements if the array length is not evenly
 divisible by the chunk size.

 - Parameter array: The array to split
 - Parameter chunkSize: The size of each chunk (must be greater than 0)
 - Returns: A new array containing the chunks
 - Throws: `SplitArrayError.invalidChunkSize` if chunkSize is less than or equal to 0
 */
public func splitArray<T>(_ array: [T], chunkSize: Int) throws -> [[T]] {
    guard chunkSize > 0 else {
        throw SplitArrayError.invalidChunkSize(chunkSize)
    }

    var result: [[T]] = []
    var index = 0

    while index < array.count {
        let end = min(index + chunkSize, array.count)
        result.append(Array(array[index..<end]))
        index += chunkSize
    }

    return result
}

/// Errors that can occur when splitting an array
public enum SplitArrayError: Error, Equatable {
    /// The chunk size must be greater than 0
    case invalidChunkSize(Int)
}

extension SplitArrayError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidChunkSize:
            return "chunkSize must be greater than 0"
        }
    }
}

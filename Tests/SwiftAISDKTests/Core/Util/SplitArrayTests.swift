import Testing
@testable import SwiftAISDK

@Suite("splitArray function tests")
struct SplitArrayTests {

    @Test("splits an array into chunks of the specified size")
    func splitsArrayIntoChunks() throws {
        let array = [1, 2, 3, 4, 5]
        let result = try splitArray(array, chunkSize: 2)
        #expect(result == [[1, 2], [3, 4], [5]])
    }

    @Test("returns empty array when input array is empty")
    func returnsEmptyArrayForEmptyInput() throws {
        let array: [Int] = []
        let result = try splitArray(array, chunkSize: 2)
        #expect(result.isEmpty)
    }

    @Test("returns original array when chunk size is greater than array length")
    func returnsOriginalArrayWhenChunkSizeIsGreater() throws {
        let array = [1, 2, 3]
        let result = try splitArray(array, chunkSize: 5)
        #expect(result == [[1, 2, 3]])
    }

    @Test("returns original array when chunk size equals array length")
    func returnsOriginalArrayWhenChunkSizeEquals() throws {
        let array = [1, 2, 3]
        let result = try splitArray(array, chunkSize: 3)
        #expect(result == [[1, 2, 3]])
    }

    @Test("handles chunk size of 1 correctly")
    func handlesChunkSizeOfOne() throws {
        let array = [1, 2, 3]
        let result = try splitArray(array, chunkSize: 1)
        #expect(result == [[1], [2], [3]])
    }

    @Test("throws error for chunk size of 0")
    func throwsErrorForChunkSizeZero() {
        let array = [1, 2, 3]
        #expect(throws: SplitArrayError.self) {
            _ = try splitArray(array, chunkSize: 0)
        }
    }

    @Test("throws error for negative chunk size")
    func throwsErrorForNegativeChunkSize() {
        let array = [1, 2, 3]
        #expect(throws: SplitArrayError.self) {
            _ = try splitArray(array, chunkSize: -1)
        }
    }

    @Test("error message is correct")
    func errorMessageIsCorrect() {
        let error = SplitArrayError.invalidChunkSize(0)
        #expect(error.localizedDescription == "chunkSize must be greater than 0")
    }
}

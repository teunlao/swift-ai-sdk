import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import SwiftAISDK

/**
 Tests for cosine similarity calculation.

 Port of tests from `@ai-sdk/ai/src/util/cosine-similarity.test.ts`.
 */
@Suite("CosineSimilarity Tests")
struct CosineSimilarityTests {

    @Test("should calculate cosine similarity correctly")
    func testCalculateCosineSimilarity() throws {
        let vector1 = [1.0, 2.0, 3.0]
        let vector2 = [4.0, 5.0, 6.0]

        let result = try cosineSimilarity(vector1: vector1, vector2: vector2)

        #expect(abs(result - 0.9746318461970762) < 0.00001)
    }

    @Test("should calculate negative cosine similarity correctly")
    func testNegativeCosineSimilarity() throws {
        let vector1 = [1.0, 0.0]
        let vector2 = [-1.0, 0.0]

        let result = try cosineSimilarity(vector1: vector1, vector2: vector2)

        #expect(abs(result - (-1.0)) < 0.00001)
    }

    @Test("should throw an error when vectors have different lengths")
    func testDifferentLengthsThrowsError() throws {
        let vector1 = [1.0, 2.0, 3.0]
        let vector2 = [4.0, 5.0]

        do {
            _ = try cosineSimilarity(vector1: vector1, vector2: vector2)
            Issue.record("Expected InvalidArgumentError to be thrown")
        } catch {
            guard let error = error as? InvalidArgumentError else {
                Issue.record("Expected InvalidArgumentError, got \(type(of: error))")
                return
            }
            if error.parameter != "vector1,vector2" {
                Issue.record("Expected parameter to be vector1,vector2 but was \(error.parameter)")
            }
        }
    }

    @Test("should give 0 when one of the vectors is a zero vector")
    func testZeroVector() throws {
        let vector1 = [0.0, 1.0, 2.0]
        let vector2 = [0.0, 0.0, 0.0]

        let result = try cosineSimilarity(vector1: vector1, vector2: vector2)
        #expect(result == 0)

        let result2 = try cosineSimilarity(vector1: vector2, vector2: vector1)
        #expect(result2 == 0)
    }

    @Test("should handle vectors with very small magnitudes")
    func testVerySmallMagnitudes() throws {
        let vector1 = [1e-10, 0.0, 0.0]
        let vector2 = [2e-10, 0.0, 0.0]

        let result = try cosineSimilarity(vector1: vector1, vector2: vector2)
        #expect(result == 1.0)

        let vector3 = [1e-10, 0.0, 0.0]
        let vector4 = [-1e-10, 0.0, 0.0]

        let result2 = try cosineSimilarity(vector1: vector3, vector2: vector4)
        #expect(result2 == -1.0)
    }
}

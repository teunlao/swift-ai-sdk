import Foundation
import AISDKProvider
import AISDKProviderUtils

/**
 Calculates the cosine similarity between two vectors.

 Port of `@ai-sdk/ai/src/util/cosine-similarity.ts`.

 Cosine similarity is a useful metric for comparing the similarity of two vectors
 such as embeddings. It measures the cosine of the angle between two vectors in
 an inner product space.

 - Parameters:
   - vector1: The first vector
   - vector2: The second vector

 - Returns: The cosine similarity between vector1 and vector2 (range: -1 to 1)
   - Returns 0 if either vector is the zero vector

 - Throws: `InvalidArgumentError` if the vectors do not have the same length

 - Note: The result is a value between -1 and 1:
   - 1: vectors point in the same direction
   - 0: vectors are orthogonal (perpendicular)
   - -1: vectors point in opposite directions

 Example:
 ```swift
 let v1 = [1.0, 2.0, 3.0]
 let v2 = [4.0, 5.0, 6.0]
 let similarity = try cosineSimilarity(vector1: v1, vector2: v2)
 // similarity ≈ 0.9746
 ```
 */
public func cosineSimilarity(vector1: [Double], vector2: [Double]) throws -> Double {
    if vector1.count != vector2.count {
        throw InvalidArgumentError(
            parameter: "vector1,vector2",
            value: .object([
                "vector1Length": .number(Double(vector1.count)),
                "vector2Length": .number(Double(vector2.count))
            ]),
            message: "Vectors must have the same length"
        )
    }

    let n = vector1.count

    if n == 0 {
        return 0 // Return 0 for empty vectors
    }

    var magnitudeSquared1: Double = 0
    var magnitudeSquared2: Double = 0
    var dotProduct: Double = 0

    for i in 0..<n {
        let value1 = vector1[i]
        let value2 = vector2[i]

        magnitudeSquared1 += value1 * value1
        magnitudeSquared2 += value2 * value2
        dotProduct += value1 * value2
    }

    // Handle zero vectors
    if magnitudeSquared1 == 0 || magnitudeSquared2 == 0 {
        return 0
    }

    return dotProduct / (magnitudeSquared1.squareRoot() * magnitudeSquared2.squareRoot())
}

import Foundation

@inlinable
func getGoogleModelPath(_ modelId: String) -> String {
    return modelId.contains("/") ? modelId : "models/\(modelId)"
}

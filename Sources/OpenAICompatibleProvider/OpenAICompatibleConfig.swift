import Foundation
import AISDKProviderUtils

public struct OpenAICompatibleURLOptions: Sendable {
    public let modelId: String
    public let path: String

    public init(modelId: String, path: String) {
        self.modelId = modelId
        self.path = path
    }
}

import Foundation
import AISDKProvider
import AISDKProviderUtils

struct OpenAISpeechAPITypes: Sendable, Equatable {
    var voice: String?
    var speed: Double?
    var responseFormat: String?
    var instructions: String?
}

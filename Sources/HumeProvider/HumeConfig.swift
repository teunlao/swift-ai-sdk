import Foundation
import AISDKProviderUtils

struct HumeConfig: Sendable {
    let provider: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var currentDate: @Sendable () -> Date = { Date() }
}

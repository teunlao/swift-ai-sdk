import AISDKProviderUtils

struct AlibabaConfig: Sendable {
    let provider: String
    let baseURL: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    var includeUsage: Bool = false
}

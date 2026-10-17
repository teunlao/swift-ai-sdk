import AISDKProvider
import AISDKProviderUtils

struct OpenResponsesConfig: Sendable {
    let provider: String
    let providerOptionsName: String
    let url: String
    let headers: @Sendable () throws -> [String: String?]
    let fetch: FetchFunction?
    let failedResponseHandler: ResponseHandler<APICallError>?
    let getResponseErrorMetadata: (@Sendable (OpenResponsesResponseError) throws -> OpenResponsesResponseErrorMetadata)?
    let generateId: IDGenerator
    let extensions: OpenResponsesExtensionRegistry
    let strictResponseInput: Bool
    let customToolId: String
    let structuredOutputs: Bool
}

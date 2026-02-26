import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/extract-api-call-response.ts
// Upstream commit: 73d5c5920
//===----------------------------------------------------------------------===//

func extractApiCallResponse(_ error: APICallError) -> Any {
    if let data = error.data {
        if let json = data as? JSONValue {
            return jsonValueToFoundation(json)
        }
        return data
    }

    if let responseBody = error.responseBody {
        if let bodyData = responseBody.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: bodyData, options: [.fragmentsAllowed]) {
            return json
        }
        return responseBody
    }

    return [:]
}

import Foundation
import AISDKProvider

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/gateway/src/errors/extract-api-call-response.ts
// Upstream commit: 77db222ee
//===----------------------------------------------------------------------===//

func extractApiCallResponse(_ error: APICallError) -> Any {
    if let data = error.data {
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

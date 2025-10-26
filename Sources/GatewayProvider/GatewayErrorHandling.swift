import Foundation
import AISDKProvider
import AISDKProviderUtils

private let gatewayErrorSchema = FlexibleSchema(
    Schema<JSONValue>.codable(
        JSONValue.self,
        jsonSchema: .object(["type": .string("object")])
    )
)

func gatewayErrorMessage(from value: JSONValue) -> String {
    switch value {
    case .string(let text):
        return text
    case .object(let dictionary):
        if case .string(let message)? = dictionary["message"] {
            return message
        }
        return String(describing: jsonValueToFoundation(.object(dictionary)))
    default:
        return String(describing: jsonValueToFoundation(value))
    }
}

func makeGatewayFailedResponseHandler() -> ResponseHandler<APICallError> {
    createJsonErrorResponseHandler(
        errorSchema: gatewayErrorSchema,
        errorToMessage: { gatewayErrorMessage(from: $0) }
    )
}

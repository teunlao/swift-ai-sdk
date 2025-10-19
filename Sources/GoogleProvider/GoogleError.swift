import Foundation
import AISDKProvider
import AISDKProviderUtils

public struct GoogleErrorData: Sendable, Equatable {
    public struct ErrorBody: Sendable, Equatable {
        public let code: Double?
        public let message: String
        public let status: String

        public init(code: Double?, message: String, status: String) {
            self.code = code
            self.message = message
            self.status = status
        }
    }

    public let error: ErrorBody

    public init(error: ErrorBody) {
        self.error = error
    }
}

private let googleErrorSchema = FlexibleSchema(
    Schema<GoogleErrorData>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "properties": .object([
                    "error": .object([
                        "type": .string("object"),
                        "properties": .object([
                            "code": .object([
                                "type": .array([.string("number"), .string("null")])
                            ]),
                            "message": .object([
                                "type": .string("string")
                            ]),
                            "status": .object([
                                "type": .string("string")
                            ])
                        ]),
                        "required": .array([
                            .string("message"),
                            .string("status")
                        ])
                    ])
                ]),
                "required": .array([
                    .string("error")
                ])
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json,
                      case .object(let errorObject)? = dict["error"] else {
                    let error = SchemaValidationIssuesError(vendor: "google", issues: "error response must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                let code: Double?
                if let codeValue = errorObject["code"], codeValue != .null {
                    guard case .number(let number) = codeValue else {
                        let error = SchemaValidationIssuesError(vendor: "google", issues: "error.code must be a number")
                        return .failure(error: TypeValidationError.wrap(value: codeValue, cause: error))
                    }
                    code = number
                } else {
                    code = nil
                }

                guard let messageValue = errorObject["message"], case .string(let message) = messageValue else {
                    let error = SchemaValidationIssuesError(vendor: "google", issues: "error.message must be a string")
                    return .failure(error: TypeValidationError.wrap(value: errorObject["message"] ?? .null, cause: error))
                }

                guard let statusValue = errorObject["status"], case .string(let status) = statusValue else {
                    let error = SchemaValidationIssuesError(vendor: "google", issues: "error.status must be a string")
                    return .failure(error: TypeValidationError.wrap(value: errorObject["status"] ?? .null, cause: error))
                }

                let data = GoogleErrorData(error: .init(code: code, message: message, status: status))
                return .success(value: data)
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

public let googleFailedResponseHandler = createJsonErrorResponseHandler(
    errorSchema: googleErrorSchema,
    errorToMessage: { (data: GoogleErrorData) in data.error.message }
)

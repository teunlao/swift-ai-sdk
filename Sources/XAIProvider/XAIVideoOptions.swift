import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/xai/src/xai-video-options.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

struct XAIVideoModelOptions: Sendable, Equatable {
    var pollIntervalMs: Double?
    var pollTimeoutMs: Double?
    var resolution: String?
    var videoUrl: String?

    /// Full raw provider options object (passthrough keys preserved).
    var raw: [String: JSONValue]
}

private let xaiVideoModelOptionsFlexibleSchema = FlexibleSchema(
    Schema<XAIVideoModelOptions>(
        jsonSchemaResolver: {
            .object([
                "type": .string("object"),
                "additionalProperties": .bool(true),
            ])
        },
        validator: { value in
            do {
                let json = try jsonValue(from: value)
                guard case .object(let dict) = json else {
                    let error = SchemaValidationIssuesError(vendor: "xai", issues: "provider options must be an object")
                    return .failure(error: TypeValidationError.wrap(value: value, cause: error))
                }

                func positiveNumberNullish(_ key: String) -> Result<Double?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .number(let number) = raw, number > 0 else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a positive number")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(number)
                }

                func stringNullish(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let str) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(str)
                }

                func resolutionNullish(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key], raw != .null else { return .success(nil) }
                    guard case .string(let str) = raw, ["480p", "720p"].contains(str) else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be '480p' or '720p'")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(str)
                }

                return .success(value: XAIVideoModelOptions(
                    pollIntervalMs: try positiveNumberNullish("pollIntervalMs").get(),
                    pollTimeoutMs: try positiveNumberNullish("pollTimeoutMs").get(),
                    resolution: try resolutionNullish("resolution").get(),
                    videoUrl: try stringNullish("videoUrl").get(),
                    raw: dict
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

let xaiVideoModelOptionsSchema = xaiVideoModelOptionsFlexibleSchema


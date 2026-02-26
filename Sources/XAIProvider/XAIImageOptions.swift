import Foundation
import AISDKProvider
import AISDKProviderUtils

//===----------------------------------------------------------------------===//
//=== Upstream Reference ====================================================//
//===----------------------------------------------------------------------===//
// Ported from packages/xai/src/xai-image-options.ts
// Upstream commit: 73d5c59
//===----------------------------------------------------------------------===//

struct XAIImageModelOptions: Sendable, Equatable {
    var aspectRatio: String?
    var outputFormat: String?
    var syncMode: Bool?
}

private let xaiImageModelOptionsFlexibleSchema = FlexibleSchema(
    Schema<XAIImageModelOptions>(
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

                func optionalString(_ key: String) -> Result<String?, TypeValidationError> {
                    guard let raw = dict[key] else { return .success(nil) }
                    if raw == .null {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard case .string(let str) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a string")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(str)
                }

                func optionalBool(_ key: String) -> Result<Bool?, TypeValidationError> {
                    guard let raw = dict[key] else { return .success(nil) }
                    if raw == .null {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    guard case .bool(let bool) = raw else {
                        let error = SchemaValidationIssuesError(vendor: "xai", issues: "\(key) must be a boolean")
                        return .failure(TypeValidationError.wrap(value: raw, cause: error))
                    }
                    return .success(bool)
                }

                return .success(value: XAIImageModelOptions(
                    aspectRatio: try optionalString("aspect_ratio").get(),
                    outputFormat: try optionalString("output_format").get(),
                    syncMode: try optionalBool("sync_mode").get()
                ))
            } catch {
                return .failure(error: TypeValidationError.wrap(value: value, cause: error))
            }
        }
    )
)

let xaiImageModelOptionsSchema = xaiImageModelOptionsFlexibleSchema


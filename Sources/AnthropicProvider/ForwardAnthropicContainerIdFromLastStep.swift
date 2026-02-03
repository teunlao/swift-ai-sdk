import Foundation
import AISDKProvider

/**
 Sets the Anthropic container ID in provider options based on previous step metadata.

 Port of `external/vercel-ai-sdk/packages/anthropic/src/forward-anthropic-container-id-from-last-step.ts`.

 This helper is intended for use in `prepareStep` where you want to forward the
 container ID between steps (e.g. when using code execution tools).
 */
public func forwardAnthropicContainerIdFromLastStep(
    steps: [SharedV3ProviderMetadata?]
) -> SharedV3ProviderOptions? {
    for metadata in steps.reversed() {
        guard let metadata,
              let anthropic = metadata["anthropic"],
              case .object(let container)? = anthropic["container"],
              case .string(let id)? = container["id"],
              !id.isEmpty
        else {
            continue
        }

        return [
            "anthropic": [
                "container": .object([
                    "id": .string(id),
                ])
            ]
        ]
    }

    return nil
}


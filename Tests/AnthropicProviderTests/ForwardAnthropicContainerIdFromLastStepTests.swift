import Testing
@testable import AnthropicProvider
import AISDKProvider

@Suite("forwardAnthropicContainerIdFromLastStep")
struct ForwardAnthropicContainerIdFromLastStepTests {
    @Test("returns providerOptions for the most recent container id")
    func returnsMostRecent() {
        let older: SharedV3ProviderMetadata = [
            "anthropic": [
                "container": .object([
                    "id": .string("container-old"),
                ])
            ]
        ]

        let newer: SharedV3ProviderMetadata = [
            "anthropic": [
                "container": .object([
                    "id": .string("container-new"),
                ])
            ]
        ]

        let result = forwardAnthropicContainerIdFromLastStep(
            steps: [older, nil, newer]
        )

        let expected: SharedV3ProviderOptions = [
            "anthropic": [
                "container": .object([
                    "id": .string("container-new"),
                ])
            ]
        ]

        #expect(result == expected)
    }

    @Test("returns nil when no container id is present")
    func returnsNilWhenAbsent() {
        let metadata: SharedV3ProviderMetadata = [
            "anthropic": [
                "container": .null
            ]
        ]

        let result = forwardAnthropicContainerIdFromLastStep(
            steps: [nil, metadata]
        )

        #expect(result == nil)
    }
}


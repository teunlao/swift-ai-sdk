import Testing
@testable import AISDKProvider
@testable import OpenAICompatibleProvider

@Suite("OpenAI-compatible provider option keys")
struct OpenAICompatibleProviderOptionKeysTests {
    @Test("converts upstream provider-name cases to camel case")
    func convertsProviderNamesToCamelCase() {
        let cases = [
            ("provider-name", "providerName"),
            ("provider_name", "providerName"),
            ("my-provider-name", "myProviderName"),
            ("providerName", "providerName"),
            ("openai", "openai"),
            ("", "")
        ]

        for testCase in cases {
            #expect(openAICompatibleCamelCase(testCase.0) == testCase.1)
        }
    }

    @Test("resolves the metadata key from supplied provider options")
    func resolvesProviderOptionsKey() {
        #expect(openAICompatibleProviderOptionsKey(
            rawName: "provider-name",
            providerOptions: ["providerName": ["value": .bool(true)]]
        ) == "providerName")
        #expect(openAICompatibleProviderOptionsKey(
            rawName: "provider-name",
            providerOptions: ["provider-name": ["value": .bool(true)]]
        ) == "provider-name")
        #expect(openAICompatibleProviderOptionsKey(
            rawName: "provider-name",
            providerOptions: [
                "provider-name": ["raw": .bool(true)],
                "providerName": ["camel": .bool(true)]
            ]
        ) == "providerName")
        #expect(openAICompatibleProviderOptionsKey(
            rawName: "provider-name",
            providerOptions: [:]
        ) == "provider-name")
        #expect(openAICompatibleProviderOptionsKey(
            rawName: "provider-name",
            providerOptions: nil
        ) == "provider-name")
        #expect(openAICompatibleProviderOptionsKey(
            rawName: "openai",
            providerOptions: ["openai": ["value": .bool(true)]]
        ) == "openai")
    }

    @Test("warns only when a distinct raw provider key is present")
    func warnsForDeprecatedRawKeys() {
        #expect(openAICompatibleDeprecatedProviderOptionsWarning(
            rawName: "black-forest-labs",
            providerOptions: ["black-forest-labs": ["style": .string("hd")]]
        ) == .deprecated(
            setting: "providerOptions key 'black-forest-labs'",
            message: "Use 'blackForestLabs' instead."
        ))
        #expect(openAICompatibleDeprecatedProviderOptionsWarning(
            rawName: "black-forest-labs",
            providerOptions: ["blackForestLabs": ["style": .string("hd")]]
        ) == nil)
        #expect(openAICompatibleDeprecatedProviderOptionsWarning(
            rawName: "openai",
            providerOptions: ["openai": ["user": .string("test")]]
        ) == nil)
        #expect(openAICompatibleDeprecatedProviderOptionsWarning(
            rawName: "black-forest-labs",
            providerOptions: [:]
        ) == nil)
        #expect(openAICompatibleDeprecatedProviderOptionsWarning(
            rawName: "black-forest-labs",
            providerOptions: nil
        ) == nil)
    }
}

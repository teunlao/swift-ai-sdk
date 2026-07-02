import Foundation
import Testing

@testable import AISDKProvider
@testable import AISDKProviderUtils

@Suite("serializeModelOptions")
struct SerializeModelOptionsTests {
    @Test("returns modelId and serializable config")
    func returnsModelIdAndSerializableConfig() throws {
        let headers: ModelOptionsHeadersResolver = {
            ["x-api-key": "sk-test"]
        }
        let generateId: @Sendable () -> String = { "id" }
        let supportedUrls: @Sendable () -> [String: JSONValue] = { [:] }

        let result = try serializeModelOptions(
            modelId: "claude-sonnet-4-20250514",
            config: [
                "provider": "anthropic.messages",
                "baseURL": "https://api.anthropic.com/v1",
                "headers": headers,
                "fetch": nil,
                "generateId": generateId,
                "supportedUrls": supportedUrls,
                "supportsNativeStructuredOutput": true,
                "supportsStrictTools": false,
            ]
        )

        #expect(result == SerializedModelOptions(
            modelId: "claude-sonnet-4-20250514",
            config: [
                "provider": "anthropic.messages",
                "baseURL": "https://api.anthropic.com/v1",
                "headers": [
                    "x-api-key": "sk-test"
                ],
                "supportsNativeStructuredOutput": true,
                "supportsStrictTools": false,
            ]
        ))
    }

    @Test("resolves headers functions but filters out other functions")
    func resolvesOnlyHeadersFunctions() throws {
        let headers: ModelOptionsHeadersResolver = {
            ["authorization": "Bearer sk-test"]
        }
        let url: @Sendable () -> String = {
            "https://api.openai.com/v1/chat/completions"
        }

        let result = try serializeModelOptions(
            modelId: "gpt-4",
            config: [
                "provider": "openai",
                "headers": headers,
                "url": url,
            ]
        )

        #expect(result == SerializedModelOptions(
            modelId: "gpt-4",
            config: [
                "provider": "openai",
                "headers": [
                    "authorization": "Bearer sk-test"
                ],
            ]
        ))
    }

    @Test("filters out objects containing non-serializable values")
    func filtersObjectsContainingNonSerializableValues() throws {
        let errorToMessage: @Sendable () -> String = { "error" }
        let createStreamExtractor: @Sendable () -> [String: JSONValue] = { [:] }

        let result = try serializeModelOptions(
            modelId: "model",
            config: [
                "provider": "openai-compatible",
                "errorStructure": [
                    "errorSchema": JSONValue.object([:]),
                    "errorToMessage": errorToMessage,
                ] as [String: Any],
                "metadataExtractor": [
                    "extractMetadata": NSNull(),
                    "createStreamExtractor": createStreamExtractor,
                ] as [String: Any],
            ]
        )

        #expect(result == SerializedModelOptions(
            modelId: "model",
            config: [
                "provider": "openai-compatible"
            ]
        ))
    }

    @Test("keeps arrays of primitives")
    func keepsArraysOfPrimitives() throws {
        let fn: @Sendable () -> Void = {}

        let result = try serializeModelOptions(
            SerializeModelOptionsOptions(
                modelId: "model",
                config: [
                    "provider": "test",
                    "tags": ["a", "b"],
                    "fn": fn,
                ]
            )
        )

        #expect(result == SerializedModelOptions(
            modelId: "model",
            config: [
                "provider": "test",
                "tags": [
                    "a",
                    "b",
                ],
            ]
        ))
    }

    @Test("throws when headers resolve asynchronously")
    func throwsWhenHeadersResolveAsynchronously() throws {
        let headers: AsyncModelOptionsHeadersResolver = {
            ["x-api-key": "sk-test"]
        }

        #expect(throws: SerializeModelOptionsError.promiseReturnedFromResolveSync) {
            _ = try serializeModelOptions(
                modelId: "model",
                config: [
                    "provider": "test",
                    "headers": headers,
                ]
            )
        }
    }

    @Test("filters out class instances")
    func filtersClassInstances() throws {
        let result = try serializeModelOptions(
            modelId: "model",
            config: [
                "provider": "test",
                "date": Date(timeIntervalSince1970: 0),
                "regex": try NSRegularExpression(pattern: "test"),
            ]
        )

        #expect(result == SerializedModelOptions(
            modelId: "model",
            config: [
                "provider": "test"
            ]
        ))
    }

    @Test("omits nil header entries")
    func omitsNilHeaderEntries() throws {
        let headers: ModelOptionsHeadersResolver = {
            [
                "authorization": "Bearer sk-test",
                "x-ignore": nil,
            ]
        }

        let result = try serializeModelOptions(
            modelId: "model",
            config: [
                "provider": "test",
                "headers": headers,
            ]
        )

        #expect(result.config["headers"] == [
            "authorization": "Bearer sk-test"
        ])
    }
}

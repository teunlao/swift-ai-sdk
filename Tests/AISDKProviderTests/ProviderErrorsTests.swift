import Foundation
import Testing
@testable import AISDKProvider

/**
 * Tests for Provider Errors
 *
 * Swift port of provider error tests.
 */

@Suite("Provider Errors")
struct ProviderErrorsTests {

    // MARK: - AISDKError Protocol

    @Test("AISDKError isAISDKError works")
    func testIsAISDKError() throws {
        let error = LoadAPIKeyError(message: "test")
        #expect(isAISDKError(error))

        struct OtherError: Error {}
        #expect(!isAISDKError(OtherError()))
    }

    @Test("AISDKError hasMarker works")
    func testHasMarker() throws {
        let error = LoadAPIKeyError(message: "test")
        #expect(hasMarker(error, marker: LoadAPIKeyError.errorDomain))
        #expect(!hasMarker(error, marker: "wrong.marker"))
    }

    // MARK: - getErrorMessage

    @Test("getErrorMessage with nil")
    func testGetErrorMessageNil() throws {
        let msg = getErrorMessage(nil as Error?)
        #expect(msg == "unknown error")
    }

    @Test("getErrorMessage with String")
    func testGetErrorMessageString() throws {
        let msg = getErrorMessage("custom error" as Any)
        #expect(msg == "custom error")
    }

    @Test("getErrorMessage with Error")
    func testGetErrorMessageError() throws {
        let error = LoadAPIKeyError(message: "API key missing")
        let msg = getErrorMessage(error as Error)
        #expect(msg == "API key missing")
    }

    // MARK: - APICallError

    @Test("APICallError creation with defaults")
    func testAPICallErrorDefaults() throws {
        let error = APICallError(
            message: "Request failed",
            url: "https://api.example.com",
            requestBodyValues: nil,
            statusCode: 500
        )

        #expect(error.message == "Request failed")
        #expect(error.url == "https://api.example.com")
        #expect(error.statusCode == 500)
        #expect(error.isRetryable == true) // 500 is retryable
    }

    @Test("APICallError isRetryable for 408")
    func testAPICallErrorRetryable408() throws {
        let error = APICallError(
            message: "Timeout",
            url: "https://api.example.com",
            requestBodyValues: nil,
            statusCode: 408
        )
        #expect(error.isRetryable == true)
    }

    @Test("APICallError isRetryable for 429")
    func testAPICallErrorRetryable429() throws {
        let error = APICallError(
            message: "Rate limited",
            url: "https://api.example.com",
            requestBodyValues: nil,
            statusCode: 429
        )
        #expect(error.isRetryable == true)
    }

    @Test("APICallError not retryable for 400")
    func testAPICallErrorNotRetryable400() throws {
        let error = APICallError(
            message: "Bad request",
            url: "https://api.example.com",
            requestBodyValues: nil,
            statusCode: 400
        )
        #expect(error.isRetryable == false)
    }

    @Test("APICallError isInstance works")
    func testAPICallErrorIsInstance() throws {
        let error = APICallError(
            message: "Test",
            url: "https://api.example.com",
            requestBodyValues: nil
        )
        #expect(APICallError.isInstance(error))
        #expect(!LoadAPIKeyError.isInstance(error))
    }

    // MARK: - EmptyResponseBodyError

    @Test("EmptyResponseBodyError default message")
    func testEmptyResponseBodyErrorDefault() throws {
        let error = EmptyResponseBodyError()
        #expect(error.message == "Empty response body")
    }

    @Test("EmptyResponseBodyError custom message")
    func testEmptyResponseBodyErrorCustom() throws {
        let error = EmptyResponseBodyError(message: "Custom empty message")
        #expect(error.message == "Custom empty message")
    }

    // MARK: - InvalidArgumentError

    @Test("InvalidArgumentError creation")
    func testInvalidArgumentError() throws {
        let error = InvalidArgumentError(
            argument: "temperature",
            message: "Temperature must be between 0 and 1"
        )
        #expect(error.argument == "temperature")
        #expect(error.message == "Temperature must be between 0 and 1")
    }

    // MARK: - InvalidPromptError

    @Test("InvalidPromptError prepends 'Invalid prompt:'")
    func testInvalidPromptError() throws {
        let error = InvalidPromptError(
            prompt: "Prompt(system: nil, prompt: nil, messages: nil)",
            message: "Missing required fields"
        )
        #expect(error.message == "Invalid prompt: Missing required fields")
    }

    // MARK: - InvalidResponseDataError

    @Test("InvalidResponseDataError with custom message")
    func testInvalidResponseDataErrorCustomMessage() throws {
        let error = InvalidResponseDataError(
            data: ["bad": "data"],
            message: "Custom invalid data message"
        )
        #expect(error.message == "Custom invalid data message")
    }

    // MARK: - JSONParseError

    @Test("JSONParseError includes text and cause")
    func testJSONParseError() throws {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "Unexpected token" }
        }

        let error = JSONParseError(
            text: "{invalid json}",
            cause: DummyError()
        )

        #expect(error.text == "{invalid json}")
        #expect(error.message.contains("JSON parsing failed"))
        #expect(error.message.contains("{invalid json}"))
        #expect(error.message.contains("Unexpected token"))
    }

    // MARK: - LoadAPIKeyError

    @Test("LoadAPIKeyError message")
    func testLoadAPIKeyError() throws {
        let error = LoadAPIKeyError(message: "OPENAI_API_KEY not found")
        #expect(error.message == "OPENAI_API_KEY not found")
    }

    // MARK: - LoadSettingError

    @Test("LoadSettingError message")
    func testLoadSettingError() throws {
        let error = LoadSettingError(message: "Invalid setting value")
        #expect(error.message == "Invalid setting value")
    }

    // MARK: - NoContentGeneratedError

    @Test("NoContentGeneratedError default message")
    func testNoContentGeneratedErrorDefault() throws {
        let error = NoContentGeneratedError()
        #expect(error.message == "No content generated.")
    }

    // MARK: - NoSuchModelError

    @Test("NoSuchModelError default message")
    func testNoSuchModelErrorDefault() throws {
        let error = NoSuchModelError(
            modelId: "gpt-4",
            modelType: .languageModel
        )
        #expect(error.modelId == "gpt-4")
        #expect(error.modelType == .languageModel)
        #expect(error.message == "No such languageModel: gpt-4")
    }

    @Test("NoSuchModelError custom message")
    func testNoSuchModelErrorCustom() throws {
        let error = NoSuchModelError(
            modelId: "whisper-1",
            modelType: .transcriptionModel,
            message: "Custom model error"
        )
        #expect(error.message == "Custom model error")
    }

    // MARK: - TooManyEmbeddingValuesForCallError

    @Test("TooManyEmbeddingValuesForCallError message")
    func testTooManyEmbeddingValuesForCallError() throws {
        let error = TooManyEmbeddingValuesForCallError(
            provider: "OpenAI",
            modelId: "text-embedding-ada-002",
            maxEmbeddingsPerCall: 100,
            values: Array(repeating: "test", count: 150)
        )

        #expect(error.provider == "OpenAI")
        #expect(error.modelId == "text-embedding-ada-002")
        #expect(error.maxEmbeddingsPerCall == 100)
        #expect(error.values.count == 150)
        #expect(error.message.contains("150 values were provided"))
    }

    // MARK: - TypeValidationError

    @Test("TypeValidationError message includes value")
    func testTypeValidationError() throws {
        struct DummyError: Error, LocalizedError {
            var errorDescription: String? { "Type mismatch" }
        }

        let error = TypeValidationError(
            value: ["key": "value"],
            cause: DummyError()
        )

        #expect(error.message.contains("Type validation failed"))
        #expect(error.message.contains("Type mismatch"))
    }

    @Test("TypeValidationError wrap returns same error if matching")
    func testTypeValidationErrorWrap() throws {
        struct DummyError: Error {}

        let original = TypeValidationError(value: 42, cause: DummyError())
        let wrapped = TypeValidationError.wrap(value: 42, cause: original)

        // Should return the original error (identity check via message)
        #expect(wrapped.message == original.message)
    }

    // MARK: - UnsupportedFunctionalityError

    @Test("UnsupportedFunctionalityError default message")
    func testUnsupportedFunctionalityErrorDefault() throws {
        let error = UnsupportedFunctionalityError(functionality: "streaming")
        #expect(error.functionality == "streaming")
        #expect(error.message == "'streaming' functionality not supported.")
    }

    @Test("UnsupportedFunctionalityError custom message")
    func testUnsupportedFunctionalityErrorCustom() throws {
        let error = UnsupportedFunctionalityError(
            functionality: "tools",
            message: "Tool calling requires GPT-4"
        )
        #expect(error.message == "Tool calling requires GPT-4")
    }
}

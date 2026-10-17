import Foundation
import Testing
import AISDKProvider
import AISDKProviderUtils
import AssemblyAIProvider

@Suite("AssemblyAI provider failure contracts")
struct AssemblyAIProviderTests {
    @Test("polling HTTP errors keep the provider error message and status")
    func pollingError() async throws {
        let endpoint = TranscriptEndpoint(["error": ["message": "unavailable", "code": 1.5]], finalStatus: 503)
        let model = createAssemblyAI(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription(modelId: .universal35Pro)
        do {
            _ = try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav"))
            Issue.record("Expected API failure")
        } catch let error as APICallError {
            #expect(error.statusCode == 503)
            #expect(error.message == "unavailable")
        }
    }
    @Test("invalid transcript status refuses at the response boundary")
    func invalidStatus() async throws {
        let endpoint = TranscriptEndpoint(["id": "job", "status": "future"])
        let model = createAssemblyAI(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription(modelId: .universal35Pro)
        await #expect(throws: APICallError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav")) }
    }
    @Test("aborted transcription cannot enter upload/poll orchestration")
    func cancellation() async throws {
        let endpoint = TranscriptEndpoint(["id": "job", "status": "completed"])
        let model = createAssemblyAI(settings: .init(apiKey: "key", fetch: { try await endpoint.fetch($0) })).transcription(modelId: .universal35Pro)
        await #expect(throws: CancellationError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav", abortSignal: { true })) }
    }
    @Suite("lazy auth", .serialized)
    struct Authentication {
        @Test("missing API key fails from transcription")
        func missingKey() async throws {
            let original = getenv("ASSEMBLYAI_API_KEY").flatMap { String(validatingCString: $0) }
            unsetenv("ASSEMBLYAI_API_KEY")
            defer { if let original { setenv("ASSEMBLYAI_API_KEY", original, 1) } else { unsetenv("ASSEMBLYAI_API_KEY") } }
            let model = createAssemblyAI().transcription(modelId: .universal35Pro)
            await #expect(throws: LoadAPIKeyError.self) { try await model.doGenerate(options: .init(audio: .binary(Data()), mediaType: "audio/wav")) }
        }
    }
}

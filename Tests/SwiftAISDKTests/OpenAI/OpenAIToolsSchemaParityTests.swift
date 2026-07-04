import Testing
@testable import AISDKProvider
@testable import AISDKProviderUtils
@testable import OpenAIProvider

@Suite("OpenAI tools schema parity")
struct OpenAIToolsSchemaParityTests {
    @Test("web_search output schema accepts search queries array")
    func webSearchOutputSchemaAcceptsQueriesArray() async throws {
        let tool = openaiTools.webSearch()
        let schema = try #require(tool.outputSchema)

        let output: [String: Any] = [
            "action": [
                "type": "search",
                "queries": ["swift ai sdk", "vercel ai sdk"]
            ],
            "sources": [
                ["type": "api", "name": "search-index"]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: output, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected web_search output with queries to validate, got error: \(error)")
        }
    }

    @Test("apply_patch input schema enforces diff only for create and update")
    func applyPatchInputSchemaEnforcesOperationDiffContract() async throws {
        let schema = openaiTools.applyPatch().inputSchema

        let validCreate: [String: Any] = [
            "callId": "call_1",
            "operation": [
                "type": "create_file",
                "path": "Sources/New.swift",
                "diff": "+hello"
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: validCreate, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected create_file with diff to validate, got error: \(error)")
        }

        let validDelete: [String: Any] = [
            "callId": "call_2",
            "operation": [
                "type": "delete_file",
                "path": "Sources/Old.swift"
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: validDelete, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected delete_file without diff to validate, got error: \(error)")
        }

        let invalidUpdate: [String: Any] = [
            "callId": "call_3",
            "operation": [
                "type": "update_file",
                "path": "Sources/Existing.swift"
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalidUpdate, schema: schema)) {
        case .success:
            Issue.record("Expected update_file without diff to fail validation")
        case .failure:
            break
        }
    }

    @Test("shell output schema requires exitCode for exit outcomes")
    func shellOutputSchemaRequiresExitCodeForExitOutcome() async throws {
        let tool = openaiTools.shell()
        let schema = try #require(tool.outputSchema)

        let validExit: [String: Any] = [
            "output": [
                [
                    "stdout": "ok",
                    "stderr": "",
                    "outcome": [
                        "type": "exit",
                        "exitCode": 0
                    ]
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: validExit, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected exit outcome with exitCode to validate, got error: \(error)")
        }

        let validTimeout: [String: Any] = [
            "output": [
                [
                    "stdout": "",
                    "stderr": "timed out",
                    "outcome": [
                        "type": "timeout"
                    ]
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: validTimeout, schema: schema)) {
        case .success:
            break
        case .failure(let error, _):
            Issue.record("Expected timeout outcome without exitCode to validate, got error: \(error)")
        }

        let invalidExit: [String: Any] = [
            "output": [
                [
                    "stdout": "",
                    "stderr": "",
                    "outcome": [
                        "type": "exit"
                    ]
                ]
            ]
        ]

        switch await safeValidateTypes(ValidateTypesOptions(value: invalidExit, schema: schema)) {
        case .success:
            Issue.record("Expected exit outcome without exitCode to fail validation")
        case .failure:
            break
        }
    }

    @Test("openaiTools.shell exposes typed environment args")
    func shellFacadeEncodesTypedEnvironmentArgs() {
        let tool = openaiTools.shell(OpenAIShellArgs(environment: [
            "type": .string("containerReference"),
            "containerId": .string("cntr_123")
        ]))

        #expect(tool.id == "openai.shell")
        #expect(tool.name == "shell")
        #expect(tool.args?["environment"] == .object([
            "type": .string("containerReference"),
            "containerId": .string("cntr_123")
        ]))
    }
}

# Provider: Anthropic

- Audited against upstream commit: `f5b2b5ef497ae6c207c17bb8ff81988ef084194b`
- Upstream package: `external/vercel-ai-sdk/packages/anthropic/src/**`
- Swift implementation: `Sources/AnthropicProvider/**`

## What is verified (checked + tested)

- [x] Prompt conversion (messages/system/tools) incl. JSON tool inputs (objects, not JSON strings).
- [x] Tool call serialization (tool_use/server_tool_use) + tool result mapping.
- [x] Tool search tools + deferred tool references (regex/bm25).
- [x] Provider tools: set `supportsDeferredResults` on upstream-marked tools (code execution, web tools, tool search) for correct multi-step deferred tool result handling.
- [x] Tool name mapping parity (`toolNameMapping`) for server tools + results.
- [x] Tool schemas parity (bash/computer/text editors/tool search/code execution) — tests added in `Tests/AnthropicProviderTests/AnthropicToolSchemasTests.swift` (post `v0.10.0`, unreleased until we commit).
- [x] Streaming SSE mapping (advanced tool streaming, multi-step container id forwarding).
- [x] Model/feature gates and validation (`cache_control` usage).
- [x] Settings/provider options parity (custom provider option keys).
- [x] Web tools output shape aligned to upstream (breaking in `v0.10.0`).
- [x] Memory tool: `memory_20250818` prepare-tools payload + `context-management-2025-06-27` beta; parses `tool_use` into V3 tool-call content.
- [x] Programmatic tool calling: parse `caller` metadata for client `tool_use` blocks and inject `type=programmatic-tool-call` for server-side `code_execution` tool calls (upstream parity).

Tests live under:
- `Tests/AnthropicProviderTests/ConvertToAnthropicMessagesPromptTests.swift`
- `Tests/AnthropicProviderTests/AnthropicPrepareToolsTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelStreamAdvancedTests.swift`
- `Tests/AnthropicProviderTests/AnthropicWebToolsSchemaTests.swift`
- `Tests/AnthropicProviderTests/AnthropicToolSchemasTests.swift` (unreleased; pending commit)
- `Tests/SwiftAISDKTests/GenerateText/GenerateTextDeferredToolResultsTests.swift` (AI-level deferred provider tool results)
- `Tests/SwiftAISDKTests/GenerateText/StreamTextDeferredToolResultsTests.swift` (AI-level deferred provider tool results)

## Known gaps / TODO

- [ ] Double-check `code_execution_20250825` caller/subtool behaviors end-to-end (beyond schema + decoding).
- [ ] Add full end-to-end parity coverage for `memory_20250818` tool-use/tool-result behaviors (beyond prepare-tools).
- [ ] Error mapping audit (HTTP + API shapes) for all newer beta tool blocks.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/anthropic/src/anthropic-prepare-tools.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/convert-to-anthropic-messages-prompt.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/anthropic-messages-language-model.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/tool/*`
- Swift (key files):
  - `Sources/AnthropicProvider/AnthropicPrepareTools.swift`
  - `Sources/AnthropicProvider/ConvertToAnthropicMessagesPrompt.swift`
  - `Sources/AnthropicProvider/AnthropicMessagesLanguageModel.swift`
  - `Sources/AnthropicProvider/Tool/*`

# Provider: Anthropic

- Audited against upstream commit: `4891db8bfc583d3767831dac83439ac190c93cb0`
- Upstream package: `external/vercel-ai-sdk/packages/anthropic/src/**`
- Swift implementation: `Sources/AnthropicProvider/**`

## What is verified (checked + tested)

- [x] Auth headers + error semantics: API key is loaded lazily at request-time and missing key throws `LoadAPIKeyError` (no `fatalError`); `apiKey`/`authToken` conflict throws `InvalidArgumentError`.
- [x] Prompt conversion (messages/system/tools) incl. JSON tool inputs (objects, not JSON strings).
- [x] Assistant prompt conversion: `code_execution_20250825` subtool naming (`bash_code_execution` / `text_editor_code_execution`) and programmatic tool calling type stripping (`programmatic-tool-call`).
- [x] Tool call serialization (tool_use/server_tool_use) + tool result mapping.
- [x] Tool search tools + deferred tool references (regex/bm25).
- [x] Provider tools: set `supportsDeferredResults` on upstream-marked tools (code execution, web tools, tool search) for correct multi-step deferred tool result handling.
- [x] Tool name mapping parity (`toolNameMapping`) for server tools + results.
- [x] Tool schemas parity (bash/computer/text editors/tool search/code execution) — tests in `Tests/AnthropicProviderTests/AnthropicToolSchemasTests.swift`.
- [x] Streaming SSE mapping (advanced tool streaming, multi-step container id forwarding).
- [x] Model/feature gates and validation (`cache_control` usage).
- [x] Settings/provider options parity (custom provider option keys).
- [x] Web tools output shape aligned to upstream (breaking in `v0.10.0`).
- [x] Memory tool: `memory_20250818` prepare-tools payload + `context-management-2025-06-27` beta; parses `tool_use` into V3 tool-call content.
- [x] Programmatic tool calling: parse `caller` metadata for client `tool_use` blocks and inject `type=programmatic-tool-call` for server-side `code_execution` tool calls (upstream parity).
- [x] Tool results parity: tool results do not set `providerExecuted`; MCP tool-call/result set `dynamic: true`.
- [x] Error mapping parity: HTTP errors + SSE `error` events decode via `anthropicErrorDataSchema` (unknown fields tolerated), matching upstream.
- [x] New provider tool versions on refreshed upstream: `code_execution_20260120`, `web_fetch_20260209`, and `web_search_20260209` are now exposed in Swift tools/prepare-tools/model tool-name mapping, with direct schema + prepare + runtime conversion coverage.
- [x] Encrypted code execution parity: Anthropic `encrypted_code_execution_result` now round-trips through Swift prompt conversion and response parsing for `code_execution_20260120`.
- [x] Direct recorded fixture coverage now exercises `anthropic-mcp.1` and `anthropic-web-fetch-tool-20260209.1` in both JSON and streaming modes; streaming `server_tool_use` blocks with populated `content_block_start.input` now preserve that input through the emitted V3 `tool-call`.
- [x] Files API parity: `AnthropicProvider.files()` now exposes a v4 files surface that uploads multipart payloads to `/v1/files` with `files-api-2025-04-14`, preserves Anthropic file metadata in `providerMetadata`, and returns provider references for reuse in later prompts.
- [x] Skills API parity: `AnthropicProvider.skills()` now exposes a v4 skills surface that uploads multipart skill bundles to `/v1/skills` with `skills-2025-10-02`, fetches latest version metadata, and maps `displayTitle` / `name` / `description` / `latestVersion` / provider metadata like upstream.

Tests live under:
- `Tests/AnthropicProviderTests/ConvertToAnthropicMessagesPromptTests.swift`
- `Tests/AnthropicProviderTests/AnthropicPrepareToolsTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesLanguageModelStreamAdvancedTests.swift`
- `Tests/AnthropicProviderTests/AnthropicMessagesFixtureTests.swift`
- `Tests/AnthropicProviderTests/AnthropicWebToolsSchemaTests.swift`
- `Tests/AnthropicProviderTests/AnthropicToolSchemasTests.swift`
- `Tests/AnthropicProviderTests/AnthropicProviderAuthErrorTests.swift`
- `Tests/AnthropicProviderTests/AnthropicFilesTests.swift`
- `Tests/AnthropicProviderTests/AnthropicSkillsTests.swift`
- `Tests/SwiftAISDKTests/GenerateText/GenerateTextDeferredToolResultsTests.swift` (AI-level deferred provider tool results)
- `Tests/SwiftAISDKTests/GenerateText/StreamTextDeferredToolResultsTests.swift` (AI-level deferred provider tool results)

## Known gaps / TODO

- [x] `code_execution_20250825` caller/subtool behaviors end-to-end (request + response mapping).
- [x] `memory_20250818` tool-use coverage (request beta + tool_use parsing).
- None known.

## Notes

- Upstream (key files):
  - `external/vercel-ai-sdk/packages/anthropic/src/anthropic-prepare-tools.ts`
  - `external/vercel-ai-sdk/packages/anthropic/src/convert-to-anthropic-messages-prompt.ts`
- `external/vercel-ai-sdk/packages/anthropic/src/anthropic-messages-language-model.ts`
- `external/vercel-ai-sdk/packages/anthropic/src/tool/*`
- `external/vercel-ai-sdk/packages/anthropic/src/anthropic-files.ts`
- `external/vercel-ai-sdk/packages/anthropic/src/skills/*`
- Swift (key files):
  - `Sources/AnthropicProvider/AnthropicPrepareTools.swift`
  - `Sources/AnthropicProvider/ConvertToAnthropicMessagesPrompt.swift`
  - `Sources/AnthropicProvider/AnthropicMessagesLanguageModel.swift`
  - `Sources/AnthropicProvider/Tool/*`
  - `Sources/AnthropicProvider/AnthropicFiles.swift`
  - `Sources/AnthropicProvider/Skills/*`
